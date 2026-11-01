#!/usr/bin/env bash
# orca-relay — run the Orca desktop app headless on this box, as the host the
# Orca Mobile app pairs with through Orca Relay. Setup steps (sign-in, phone
# pairing, connecting the laptop): ORCA-RELAY.md in the devbox repo.
#
# Why the desktop app and not `orca-ide serve`
# --------------------------------------------
# Orca Relay is what lets the phone reach this box with no inbound port, no
# Tailscale, and the laptop closed. In Orca's source (main-process-runtime-
# launch.ts) only desktop mode starts it: launchDesktopMode() calls
# startDesktopRelayService(), launchServeMode() never does, and its comment says
# a serve host "dispatches no push notifications". `orca-ide serve` therefore
# only pairs a phone that can dial port 6768 directly. So this box runs the full
# desktop app on a virtual X display (Xvfb). Nobody looks at that display except
# through `orca-relay vnc`, which is only needed to sign in, pair the phone, and
# change settings.
#
# Why a keyring
# -------------
# Orca keeps its account session (the thing Relay authenticates with) sealed by
# Electron safeStorage. With no Secret Service on the session bus, safeStorage
# is unavailable and a packaged build refuses to fall back to plaintext: the
# session is held in memory only, and every restart signs Relay out. So each run
# gets a private D-Bus session with gnome-keyring unlocked by a password that is
# generated once and kept beside the keyring in /home/dev. That is no stronger
# than plaintext against someone already inside this box, and is not meant to
# be. It exists so the login survives restarts.
#
# Subcommands (run as dev):
#   run                   start Xvfb + keyring + Orca in the foreground (entrypoint.sh)
#   status                is it up, is Relay connected, the last sign-in link
#   vnc                   serve the display on 127.0.0.1:5900 until Ctrl-C
#   callback <url>        finish a sign-in done in another machine's browser
#   add-projects [dir…]   register git repos with Orca (default: every
#                         /home/*/.superset/projects/* repo)
#
# Invoked as `orca-relay-browser` (a symlink; Orca's $BROWSER) it records the URL
# Orca wants opened and shows it in a Chromium window on the virtual display.
set -euo pipefail

# Overrides live under DEVBOX_ORCA_*, never ORCA_*: Orca reads ORCA_* itself
# (ORCA_RELAY_PATH among them), and scrub_orca_env clears that namespace.
APP_BIN=${DEVBOX_ORCA_APP:-/opt/Orca/orca-ide}
# The CLI by absolute path: a laptop that uses this box as an SSH host installs
# its own orca-ide shim in ~/.orca/cli/bin, ahead of /usr/bin on PATH, and that
# one talks to the laptop's runtime, not this one.
CLI_BIN=${DEVBOX_ORCA_CLI:-/usr/bin/orca-ide}
DISPLAY_NUM=${DEVBOX_ORCA_DISPLAY:-:77}
SCREEN_GEOMETRY=${DEVBOX_ORCA_GEOMETRY:-1920x1080x24}
VNC_PORT=${DEVBOX_ORCA_VNC_PORT:-5900}
STATE_DIR="$HOME/.local/share/devbox-orca"      # persistent: keyring password, browser profile
RUN_DIR="/tmp/devbox-orca-$(id -u)"              # per boot: last sign-in URL
KEYRING_DIR="$HOME/.local/share/keyrings"
LOG=${DEVBOX_ORCA_LOG:-/var/log/orca.log}           # entrypoint.sh sends Orca's output here

say() { printf '[orca-relay] %s\n' "$*"; }
die() { printf 'orca-relay: %s\n' "$*" >&2; exit 1; }

display_socket() { printf '/tmp/.X11-unix/X%s' "${DISPLAY_NUM#:}"; }

xvfb_alive() {
  local lock="/tmp/.X${DISPLAY_NUM#:}-lock" pid
  [ -r "$lock" ] || return 1
  pid="$(tr -d ' \n' < "$lock")"
  [ -n "$pid" ] && [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = Xvfb ]
}

# A shell inside any Orca terminal carries that runtime's ORCA_* variables, and
# ORCA_USER_DATA_PATH in particular steers both the CLI and the app at that
# runtime's state. Run from a terminal a laptop opened here over SSH, the CLI
# would register repos with the laptop, not with this box. Start from none.
scrub_orca_env() {
  local v
  for v in $(compgen -e); do
    case "$v" in ORCA_*) unset "$v" ;; esac
  done
}

# --password-store: Chromium cannot detect a keyring with no desktop session
# around it, and would otherwise pick basic_text (unsealed).
# --disable-gpu: Xvfb has no GL. Chromium would fall back to software after its
# GPU process failed, which is noise at best; `orca-ide serve` makes the same
# choice on Linux.
APP_FLAGS="--password-store=gnome-libsecret --disable-gpu"

# The main process, matched on its whole command line. Every Orca helper is also
# named orca-ide, and its PTY daemon is built to outlive the app so terminals
# survive a restart: matching on the name would see that daemon after a crash
# and refuse to start Orca again, forever.
orca_pid() { pgrep -u "$(id -u)" -o -xf "$APP_BIN $APP_FLAGS" 2>/dev/null || true; }

# ── run ─────────────────────────────────────────────────────────────
cmd_run() {
  [ "$(id -u)" != 0 ] || die "run as dev, not root (Orca's state belongs in dev's home)"
  [ -x "$APP_BIN" ] || die "Orca is not installed at $APP_BIN"
  [ -z "$(orca_pid)" ] || die "Orca is already running (pid $(orca_pid))"
  mkdir -p "$STATE_DIR" "$RUN_DIR" "$KEYRING_DIR"
  chmod 700 "$STATE_DIR" "$RUN_DIR"

  # The display outlives Orca on purpose: when the respawn loop restarts Orca,
  # it reuses the display, and an open `orca-relay vnc` keeps working.
  if ! xvfb_alive; then
    rm -f "/tmp/.X${DISPLAY_NUM#:}-lock" "$(display_socket)"
    Xvfb "$DISPLAY_NUM" -screen 0 "$SCREEN_GEOMETRY" -nolisten tcp >> "$RUN_DIR/xvfb.log" 2>&1 &
    disown
    for _ in $(seq 1 50); do [ -S "$(display_socket)" ] && break; sleep 0.2; done
    [ -S "$(display_socket)" ] || die "Xvfb did not come up on $DISPLAY_NUM (see $RUN_DIR/xvfb.log)"
  fi

  # A private session bus per run: the keyring daemon lives and dies with Orca,
  # so a restart never inherits a keyring left locked by an earlier run.
  exec dbus-run-session -- "$0" __session
}

# Runs inside dbus-run-session. Not a public subcommand.
cmd_session() {
  local pwfile="$STATE_DIR/keyring-password" keyring="$KEYRING_DIR/login.keyring"

  if [ ! -s "$pwfile" ]; then
    # A keyring with no password file cannot be opened headless, and the
    # libsecret prompt it would raise has no one to answer it. Set it aside so a
    # fresh one is made; the cost is signing in to Orca again.
    if [ -e "$keyring" ]; then
      mv "$keyring" "$keyring.orphaned-$(date +%s)"
      say "login keyring had no password on file; set it aside, so sign in to Orca again"
    fi
    (umask 077 && head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' > "$pwfile")
  fi

  # --unlock opens (or creates) the login keyring with the password on stdin;
  # --start then registers the Secret Service on this session bus.
  eval "$(gnome-keyring-daemon --unlock --components=secrets < "$pwfile")"
  eval "$(gnome-keyring-daemon --start --components=secrets)"
  export GNOME_KEYRING_CONTROL

  if ! keyring_unlocked; then
    # Wrong password (the file was replaced by hand, or a restore paired the
    # wrong two files). Move the keyring aside and let the respawn loop start
    # over with a fresh one, rather than run Orca with its session unsealable.
    mv "$keyring" "$keyring.unopenable-$(date +%s)"
    die "login keyring would not unlock with $pwfile; set it aside, so sign in to Orca again"
  fi

  scrub_orca_env

  # Same environment an SSH login gets (see config/zshenv). entrypoint.sh starts
  # this under `env -i`, as sshd starts shells clean, so container variables
  # reach Orca only through the env.runtime bridge, the same way they reach
  # shells. GH_TOKEN matters here: Orca's GitHub views run `gh` from this process.
  export TZ=UTC
  export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
  # shellcheck disable=SC1091
  [ -r /etc/zsh/env.runtime ] && . /etc/zsh/env.runtime
  export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  export SHELL=/bin/zsh
  export DISPLAY="$DISPLAY_NUM"
  export BROWSER=/usr/local/bin/orca-relay-browser
  # Same privacy posture as TZ=UTC: both switches are honoured by Orca's
  # telemetry and its crash/observability reporting.
  export DO_NOT_TRACK=1 ORCA_TELEMETRY_DISABLED=1

  say "starting Orca $(orca_version) on $DISPLAY_NUM"
  # shellcheck disable=SC2086  # APP_FLAGS is two plain words, split on purpose
  exec "$APP_BIN" $APP_FLAGS
}

keyring_unlocked() {
  local out
  out="$(gdbus call --session --dest org.freedesktop.secrets \
          --object-path /org/freedesktop/secrets/collection/login \
          --method org.freedesktop.DBus.Properties.Get \
          org.freedesktop.Secret.Collection Locked 2>/dev/null)" || return 1
  [ "$out" = "(<false>,)" ]
}

orca_version() {
  dpkg-query -W -f='${Version}' orca-ide 2>/dev/null || echo "(unknown version)"
}

# ── orca-relay-browser ──────────────────────────────────────────────
# Orca opens its sign-in page with shell.openExternal → xdg-open → $BROWSER, and
# fails the sign-in outright if that does not exit 0. Record the URL (so
# `status` can print it for a browser elsewhere), show it in Chromium on the
# virtual display when one is installed, and return at once.
#
# Only Orca's own sign-in page gets a browser. $BROWSER is inherited by every
# terminal and agent under Orca, so anything they open (`gh auth login --web`,
# a dev server) would otherwise start a Chromium nobody can see and leave it
# running. Those URLs are recorded and nothing more. The sign-in browser closes
# itself once Orca's loopback listener for that sign-in is gone, i.e. the login
# completed or Orca gave up on it (5 minutes), so it never lingers.
cmd_open_url() {
  local url="${1:-}" chrome port pid
  [ -n "$url" ] || exit 0
  mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"
  (umask 077 && printf '%s\n' "$url" > "$RUN_DIR/last-url")
  { say "browser requested: $url" >> "$LOG"; } 2>/dev/null || true

  case "$url" in
    https://login.onorca.dev/*/auth/authorize\?*) ;;
    *) exit 0 ;;
  esac
  chrome="$(ls -d /ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | sort -V | tail -n 1)"
  [ -n "$chrome" ] && [ -n "${DISPLAY:-}" ] || exit 0

  mkdir -p "$STATE_DIR/browser"
  nohup "$chrome" --user-data-dir="$STATE_DIR/browser" --no-first-run \
    --no-default-browser-check --disable-gpu --password-store=basic \
    --window-position=0,0 --window-size=1280,900 --new-window "$url" \
    >/dev/null 2>&1 &
  pid=$!
  disown
  port="$(printf '%s' "$url" | sed -nE 's/.*redirect_uri=http%3A%2F%2F127\.0\.0\.1%3A([0-9]+)%2F.*/\1/p')"
  nohup "$(readlink -f "$0")" __close-browser "$pid" "${port:-0}" >/dev/null 2>&1 &
  disown
  exit 0
}

loopback_listening() {
  local hex
  hex="$(printf '%04X' "$1")"
  grep -q " 0100007F:$hex 00000000:0000 0A " /proc/net/tcp 2>/dev/null
}

# Not a public subcommand: closes the sign-in browser (pid $1) once the
# sign-in's callback port ($2) stops listening, or after 10 minutes regardless.
cmd_close_browser() {
  local pid="$1" port="$2" waited=0
  sleep 5
  while [ "$waited" -lt 600 ] && kill -0 "$pid" 2>/dev/null; do
    if [ "$port" != 0 ] && ! loopback_listening "$port"; then
      sleep 3   # let the "signed in" page show before the window goes
      break
    fi
    sleep 2; waited=$((waited + 2))
  done
  kill "$pid" 2>/dev/null || true
}

# Orca starts at 6768 and walks up when that is taken (a laptop's SSH-mode orcad
# holds 6768 on this box), then remembers whatever it got, so the port has to be
# read, not assumed. It is the listener in the 67xx range: the other one the
# main process holds is the agent-hook server, on a random loopback port.
runtime_port() {
  local inode ports=""
  for inode in $(ls -l "/proc/$1/fd" 2>/dev/null | sed -nE 's/.*socket:\[([0-9]+)\].*/\1/p'); do
    ports="$ports $(awk -v i="$inode" '$10==i && $4=="0A" {split($2,a,":"); print a[2]}' /proc/net/tcp /proc/net/tcp6)"
  done
  local hex p best=""
  for hex in $ports; do
    p=$((16#$hex))
    if [ "$p" -ge 6768 ] && [ "$p" -lt 6800 ]; then best="$p"; fi
  done
  echo "${best:-unknown}"
}

# ── status ──────────────────────────────────────────────────────────
cmd_status() {
  local pid
  pid="$(orca_pid)"
  if [ -n "$pid" ]; then
    say "Orca $(orca_version) running (pid $pid) on $DISPLAY_NUM"
    say "runtime port: $(runtime_port "$pid") (what a laptop's Remote Orca Server link dials)"
  else say "Orca is not running. Recent log:"; tail -n 15 "$LOG" 2>/dev/null || true
  fi
  xvfb_alive && say "display $DISPLAY_NUM up" || say "display $DISPLAY_NUM down"

  # Two Orca runtimes on one home share ~/.orca (agent hooks, session journal).
  # Orca is not built for that, so say so when a laptop is also using this box
  # as an SSH host.
  if pgrep -u "$(id -u)" -f "$HOME/.orca-remote/.*/orcad" >/dev/null 2>&1; then
    say "WARNING: a laptop's Orca is also using this box as an SSH host (~/.orca-remote/orcad)."
    say "         Pick one: connect that laptop to this box as a Remote Orca Server instead."
  fi

  local relay
  relay="$(grep -a '\[relay\]' "$LOG" 2>/dev/null | tail -n 3 || true)"
  [ -z "$relay" ] || { say "recent Relay log lines:"; printf '  %s\n' "$relay"; }
  if [ -s "$RUN_DIR/last-url" ]; then
    say "last link Orca asked to open (valid only while that sign-in is pending):"
    printf '  %s\n' "$(cat "$RUN_DIR/last-url")"
  fi
}

# ── vnc ─────────────────────────────────────────────────────────────
cmd_vnc() {
  xvfb_alive || die "display $DISPLAY_NUM is not up; is Orca running? (orca-relay status)"
  # Orca's window comes up at its own size and, with no window manager, nothing
  # can resize it. Stretch it to the screen first.
  if command -v xdotool >/dev/null; then
    DISPLAY="$DISPLAY_NUM" xdotool search --onlyvisible --class orca \
      windowmove 0 0 windowsize 100% 100% >/dev/null 2>&1 || true
  fi
  say "VNC for $DISPLAY_NUM on 127.0.0.1:$VNC_PORT. Ctrl-C (or closing this SSH session) stops it."
  # Loopback only and no VNC password: the SSH tunnel is the authentication,
  # and nothing that reaches 127.0.0.1 here is not already dev.
  exec x11vnc -display "$DISPLAY_NUM" -localhost -rfbport "$VNC_PORT" \
    -forever -shared -nopw -noxdamage -quiet
}

# ── callback ────────────────────────────────────────────────────────
# Sign-in redirects to http://127.0.0.1:<port>/auth/callback?code=…&state=… on
# this box. If you signed in with a browser on another machine, that redirect
# lands on the wrong 127.0.0.1 and the page fails to load. Copy that URL from
# the address bar and hand it here: Orca checks `state` and completes the login.
cmd_callback() {
  local url="${1:-}"
  case "$url" in
    http://127.0.0.1:*/auth/callback\?*) ;;
    *) die "usage: orca-relay callback 'http://127.0.0.1:<port>/auth/callback?code=…&state=…'" ;;
  esac
  curl -fsS --max-time 15 -o /dev/null "$url" \
    || die "Orca did not accept it. That sign-in may have timed out; start it again in Orca."
  say "sign-in handed to Orca"
}

# ── add-projects ────────────────────────────────────────────────────
# Orca reads a repo's worktrees from `git worktree list`, but ones it did not
# create itself (every Superset worktree, and anything from new-worktree) are
# "non-Orca worktrees", hidden by default. Each repo is set to show them, so the
# existing worktrees appear in the sidebar and on the phone the moment the repo
# is added.
cmd_add_projects() {
  [ -n "$(orca_pid)" ] || die "Orca is not running (orca-relay status)"
  [ -x "$CLI_BIN" ] || die "Orca CLI not found at $CLI_BIN"
  scrub_orca_env
  if [ $# -eq 0 ]; then
    shopt -s nullglob
    set -- /home/*/.superset/projects/*/
    shopt -u nullglob
  fi
  local d
  for d in "$@"; do
    d="${d%/}"
    if [ ! -e "$d/.git" ]; then say "skip   $d (not a git repo)"; continue; fi
    if ! "$CLI_BIN" repo add --path "$d" --json >/dev/null 2>&1; then
      say "FAILED $d (try: $CLI_BIN repo add --path '$d')"
      continue
    fi
    if "$CLI_BIN" repo set --repo "path:$d" --external-worktree-visibility show --json >/dev/null 2>&1; then
      say "added  $d ($(git -C "$d" worktree list 2>/dev/null | wc -l) worktrees incl. main)"
    else
      say "added  $d, but could not unhide its existing worktrees (Non-Orca worktrees card in the sidebar)"
    fi
  done
}

case "$(basename "$0")" in
  orca-relay-browser) cmd_open_url "$@" ;;
esac

case "${1:-}" in
  run)          cmd_run ;;
  __session)    cmd_session ;;
  __close-browser) shift; cmd_close_browser "$@" ;;
  status)       cmd_status ;;
  vnc)          cmd_vnc ;;
  callback)     shift; cmd_callback "$@" ;;
  add-projects) shift; cmd_add_projects "$@" ;;
  *) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
