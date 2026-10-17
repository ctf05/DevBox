#!/usr/bin/env python3
"""ttyguard — run a command behind a pty that filters terminal capability chatter.

Why this exists
---------------
tmux probes its client terminal on every attach: DA1 (``ESC [ c``), DA2
(``ESC [ > c``) and XTVERSION (``ESC [ > q``). It then waits ~5s for the
answers. Replies that land inside that window are consumed silently; replies
that land *after* it are not — ``tty_keys_device_attributes()`` bails out once
``TTY_HAVEDA`` is set, so the bytes fall through tmux's key parser and are
delivered to the focused pane as keystrokes. The shell echoes them, ZLE
interprets stray control bytes as widgets, and the prompt fills with junk like

    ^[[?62;4;9;22c^[[>0;276;0c^[P>|xterm.js(6.1.0-beta.219)^[\

which is what `dev x` into this box used to greet you with. Two things make
late replies the norm rather than the exception here:

  * the client terminal is xterm.js in the Superset app, reached over an SSH
    tunnel — it answers when it next renders, not when asked, and
  * the app saves each pane's raw output stream and replays it on restore.
    tmux's probe bytes are *in* that stream, so a restore re-asks the terminal
    for its attributes long after any tmux is listening for the answer.

tmux 3.4 sends those probes unconditionally — not gated on TERM, terminfo
``XT``, or ``tmux -T`` (all verified on this image), so there is no option to
turn them off. Hence a filter in the pty path.

What it does
------------
Output (tmux → terminal): drop the three probes, so the terminal is never
asked and the bytes never reach the app's saved scrollback to be replayed.

Input (terminal → tmux): drop terminal *replies* — private-parameter CSI
responses (``ESC [ ?``…, ``ESC [ >``…) and DCS responses (``ESC P >``…,
``ESC P + r``…, ``ESC P $ r``…). No key on any keyboard produces these, so
dropping them cannot eat real input. SGR mouse reports (``ESC [ <``) and
bracketed paste (``ESC [ 2 0 0 ~``) do not match and pass through untouched.

The two directions back each other up: if a probe slips out (split across a
write boundary), the reply it provokes is still caught on the way in.

Everything else is relayed byte-for-byte, window size is tracked, and the
child's exit status is this process's exit status. If the pty cannot be set
up at all, the command is exec'd directly rather than failing.

Usage: ttyguard <command> [args...]
"""

import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import tty

CHUNK = 65536

# tmux's client capability probes, stripped from the output stream.
PROBES = (b"\x1b[c", b"\x1b[>c", b"\x1b[>q")

# DCS payload prefixes that mark a terminal *reply* (XTVERSION, XTGETTCAP,
# DECRPSS). Anything else after ESC P is left alone.
DCS_REPLY_PREFIXES = (b">", b"!|", b"+r", b"0+r", b"1+r", b"$r", b"0$r", b"1$r")

# Byte sequences that are too short to classify yet, so the next read gets to
# finish them. A bare ESC is among them: that costs a lone Escape keypress
# HOLD_TIMEOUT of latency, same order as tmux's own escape-time of 10ms.
AMBIGUOUS = (b"\x1b", b"\x1b[", b"\x1bP")

# How long a partial sequence waits for its continuation before being let
# through as-is, so a truncated sequence can never wedge the stream.
HOLD_TIMEOUT = 0.01


# Longest sequence either matcher will swallow. Real device reports are far
# shorter; the caps keep a corrupt stream from eating a useful span of input.
MAX_CSI = 64
MAX_DCS = 512


def _match_private_csi(rest):
    """Match ``ESC [ (? | >) <params> <final>`` at the start of ``rest``.

    Returns its length, 0 if this is not one, or -1 if it still could be once
    more bytes arrive. Parameter and intermediate bytes only (0x20-0x3F and
    0x20-0x2F): hitting anything else — a control byte the user typed while a
    stray ESC sat in the stream, say — means this is not a reply, so the bytes
    are passed through rather than swallowed.
    """
    for k in range(2, min(len(rest), MAX_CSI)):
        byte = rest[k]
        if 0x40 <= byte <= 0x7E:
            return k + 1
        if not 0x20 <= byte <= 0x3F:
            return 0
    return -1 if len(rest) < MAX_CSI else 0


def _match_dcs_reply(rest):
    """Match a DCS *reply* (``ESC P`` + known payload prefix + ``ESC \\``).

    Same return convention as :func:`_match_private_csi`. Only payloads that
    announce a terminal response are considered, so an Alt-Shift-P keypress
    followed by ordinary text is left alone.
    """
    body = rest[2:]
    if not body:
        return -1
    if not any(p.startswith(body) or body.startswith(p) for p in DCS_REPLY_PREFIXES):
        return 0
    for k in range(2, min(len(rest), MAX_DCS)):
        byte = rest[k]
        if byte == 0x1B:
            if k + 1 >= len(rest):
                return -1
            return k + 2 if rest[k + 1] == 0x5C else 0
        if byte == 0x07:
            return k + 1
        if byte < 0x20 or byte == 0x7F:
            return 0
    return -1 if len(rest) < MAX_DCS else 0


def filter_output(buf):
    """Strip tmux's capability probes. Returns (forward, withheld)."""
    out = bytearray()
    i, n = 0, len(buf)
    while i < n:
        j = buf.find(b"\x1b", i)
        if j < 0:
            out += buf[i:]
            return bytes(out), b""
        out += buf[i:j]
        rest = buf[j:]
        hit = next((p for p in PROBES if rest.startswith(p)), None)
        if hit is not None:
            i = j + len(hit)
            continue
        # A tail still on its way to being a probe waits for the next read.
        if any(p.startswith(rest) for p in PROBES):
            return bytes(out), bytes(rest)
        out += b"\x1b"
        i = j + 1
    return bytes(out), b""


def filter_input(buf):
    """Strip terminal replies. Returns (forward, withheld)."""
    out = bytearray()
    i, n = 0, len(buf)
    while i < n:
        j = buf.find(b"\x1b", i)
        if j < 0:
            out += buf[i:]
            return bytes(out), b""
        out += buf[i:j]
        rest = buf[j:]

        if rest in AMBIGUOUS:
            return bytes(out), bytes(rest)

        matched = 0
        if rest.startswith(b"\x1b[") and rest[2] in b"?>":
            matched = _match_private_csi(rest)
        elif rest.startswith(b"\x1bP"):
            matched = _match_dcs_reply(rest)

        if matched < 0:
            return bytes(out), bytes(rest)
        if matched > 0:
            i = j + matched
            continue

        out += b"\x1b"
        i = j + 1
    return bytes(out), b""


def _winsize(fd):
    try:
        return fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\x00" * 8)
    except OSError:
        return struct.pack("HHHH", 24, 80, 0, 0)


def _write_all(fd, data):
    while data:
        try:
            data = data[os.write(fd, data):]
        except InterruptedError:
            continue
        except BrokenPipeError:
            return
        except OSError:
            return


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: ttyguard <command> [args...]\n")
        return 2
    cmd = argv[1:]

    def hand_off():
        """Run the command unfiltered. Nothing here is worth failing over."""
        try:
            os.execvp(cmd[0], cmd)
        except OSError as exc:
            sys.stderr.write(f"ttyguard: {cmd[0]}: {exc.strerror}\n")
            sys.exit(127)

    # Nothing to filter without a terminal on both ends — get out of the way.
    if not (os.isatty(0) and os.isatty(1)):
        hand_off()

    try:
        master, slave = pty.openpty()
    except OSError:
        hand_off()

    try:
        termios.tcsetattr(slave, termios.TCSANOW, termios.tcgetattr(0))
    except (OSError, termios.error):
        pass
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, _winsize(0))
    except OSError:
        pass

    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.setsid()
        try:
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        except OSError:
            pass
        for target in (0, 1, 2):
            os.dup2(slave, target)
        if slave > 2:
            os.close(slave)
        try:
            os.execvp(cmd[0], cmd)
        except OSError as exc:
            sys.stderr.write(f"ttyguard: {cmd[0]}: {exc.strerror}\r\n")
        os._exit(127)

    os.close(slave)

    saved = None
    try:
        saved = termios.tcgetattr(0)
        tty.setraw(0)
    except (OSError, termios.error):
        saved = None

    # Python retries a signal-interrupted select() (PEP 475), so a handler
    # alone never wakes the loop. The wakeup pipe is what makes a resize
    # arriving during an idle select() visible.
    wake_r, wake_w = os.pipe()
    os.set_blocking(wake_r, False)
    os.set_blocking(wake_w, False)
    signal.set_wakeup_fd(wake_w)

    resized = [True]
    signal.signal(signal.SIGWINCH, lambda *_: resized.__setitem__(0, True))
    # The child has its own session, so the tty never signals it directly.
    # Anything aimed at us is meant for it. (In raw mode Ctrl-C is a byte, not
    # a signal, so SIGINT here only ever comes from outside.)
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, lambda s, _f: os.kill(pid, s))

    held_in = b""
    held_out = b""
    stdin_open = True
    try:
        while True:
            if resized[0]:
                resized[0] = False
                try:
                    fcntl.ioctl(master, termios.TIOCSWINSZ, _winsize(0))
                except OSError:
                    pass

            watch = [master, wake_r] + ([0] if stdin_open else [])
            timeout = HOLD_TIMEOUT if (held_in or held_out) else None
            try:
                ready, _, _ = select.select(watch, [], [], timeout)
            except InterruptedError:
                continue
            except OSError:
                break

            if wake_r in ready:
                try:
                    os.read(wake_r, 256)
                except OSError:
                    pass
                ready.remove(wake_r)
                if not ready:
                    continue

            if not ready:
                # Nothing followed a partial sequence — let it through rather
                # than sit on it.
                if held_out:
                    _write_all(1, held_out)
                    held_out = b""
                if held_in:
                    _write_all(master, held_in)
                    held_in = b""
                continue

            if master in ready:
                try:
                    data = os.read(master, CHUNK)
                except (OSError, InterruptedError):
                    data = b""
                if not data:
                    if held_out:
                        _write_all(1, held_out)
                        held_out = b""
                    break
                clean, held_out = filter_output(held_out + data)
                _write_all(1, clean)

            if 0 in ready:
                try:
                    data = os.read(0, CHUNK)
                except InterruptedError:
                    continue
                except OSError:
                    data = b""
                if not data:
                    # Terminal went away; keep relaying the child's output
                    # until it notices and exits.
                    stdin_open = False
                else:
                    clean, held_in = filter_input(held_in + data)
                    _write_all(master, clean)
    finally:
        signal.set_wakeup_fd(-1)
        if saved is not None:
            try:
                termios.tcsetattr(0, termios.TCSADRAIN, saved)
            except (OSError, termios.error):
                pass
        for fd in (master, wake_r, wake_w):
            try:
                os.close(fd)
            except OSError:
                pass

    while True:
        try:
            _, status = os.waitpid(pid, 0)
            break
        except InterruptedError:
            continue
        except ChildProcessError:
            return 0
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return os.WEXITSTATUS(status)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
