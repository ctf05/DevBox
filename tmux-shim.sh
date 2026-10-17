#!/bin/sh
# /usr/local/bin/tmux — run the real tmux behind ttyguard.
#
# tmux 3.4 probes its client terminal for device attributes on every attach and
# hands any late answer to the focused pane as keystrokes (see ttyguard's
# header for the full story). That is why attaching from the Superset app used
# to spray `^[[?62;4;9;22c^[[>0;276;0c^[P>|xterm.js(...)^[\` across the prompt.
# The probes are not configurable, so the client runs behind a filtering pty.
#
# Only an interactive, outside-tmux invocation is wrapped: that is the one that
# starts a tmux *client* and therefore the one that probes. Scripted calls
# (`tmux ls` into a pipe), calls from inside a session ($TMUX set), and
# anything running without a terminal exec the real binary directly, so tmux
# behaves exactly as before everywhere else.
#
# Escape hatch: DEVBOX_TTYGUARD=0 bypasses the wrapper entirely.

REAL=/usr/bin/tmux
[ -x "$REAL" ] || REAL=/bin/tmux

if [ "${DEVBOX_TTYGUARD:-1}" = 1 ] &&
   [ -z "$TMUX" ] &&
   [ -t 0 ] && [ -t 1 ] &&
   [ -x /usr/local/bin/ttyguard ] &&
   [ -x "$REAL" ]
then
  exec /usr/local/bin/ttyguard "$REAL" "$@"
fi

exec "$REAL" "$@"
