#!/usr/bin/env bash
# devbox-backup — restic backups of this box every 10 minutes, the same backup
# the laptop runs from the dotfiles repo (modules/restic-backup.nix): same
# restic flags, same retention, a different repo.
#
# Where it goes
# -------------
# A restic rest-server on the same Unraid host, reached over the shared Docker
# network by container name, so no Cloudflare hop. It is a separate repo from
# the laptop's, served by its own rest-server, so that these credentials can
# never reach the laptop's backups: anything with sudo in this box can read
# them, and agents here have sudo.
#
# What it covers
# --------------
# Everything that does not come back from the image: the four devkeep datasets.
#   /home/dev        dev's home (Claude transcripts and settings, shell history)
#   /workspace       client homes, i.e. every synced repo and worktree. /home and
#                    /Users are binds of this, so it is backed up once, here.
#   /etc/ssh/keys    sshd host keys
#   /run/secrets     mounted secrets (git key)
# Not covered: /var/lib/docker and /tmp (devscratch: per-worktree e2e databases
# and images that compose recreates), and the image itself (rebuilt from this
# repo; ghcr keeps every :sha tag).
#
# Configuration (Unraid container variables)
# ------------------------------------------
#   BACKUP_RESTIC_PASSWORD  repo passphrase — encrypts the backups. Required.
#                           Lose it and the backups are unreadable: keep it in
#                           a password manager too.
#   BACKUP_REST_PASSWORD    rest-server login (its .htpasswd). Required.
#   BACKUP_REST_USER        rest-server user (default: devbox)
#   BACKUP_REPO             rest: URL without credentials
#                           (default: rest:http://restic-rest-server-devbox:8000/)
#   BACKUP_HOST             snapshot host name (default: devbox)
#   BACKUP_ENABLED          0/false/no/off stops the schedule (entrypoint.sh)
# entrypoint.sh copies these at boot into a root-only file on a tmpfs, $ENV_FILE,
# and takes the passwords out of its own environment, so no other process it
# starts inherits them. Changing a variable needs a container restart, like
# every other variable on this box.
#
# Subcommands (as root: sudo devbox-backup …):
#   run          back up now, in the foreground (waits for no schedule)
#   status       is the schedule up, how did the last run go, latest snapshots
#   restic …     any restic command against the repo, e.g.
#                  sudo devbox-backup restic snapshots
#                  sudo devbox-backup restic restore latest --target /tmp/r --include /home/dev/.zsh_history
#   loop         the 10-minute schedule (entrypoint.sh runs it)
set -euo pipefail

STATE_DIR=${DEVBOX_BACKUP_STATE:-/run/devbox-backup}   # tmpfs, written by entrypoint.sh
ENV_FILE="$STATE_DIR/env"
LOCK_FILE="$STATE_DIR/lock"
LAST_FILE="$STATE_DIR/last"
LOG=${DEVBOX_BACKUP_LOG:-/var/log/devbox-backup.log}
LOG_MAX_BYTES=$((20 * 1024 * 1024))
RESTIC=${DEVBOX_BACKUP_RESTIC:-/usr/local/bin/restic}

# The restic cache saves re-downloading the repo's index and the parent
# snapshot's trees every run. Kept on the persistent home dataset so a container
# update doesn't cost one slow run; it is excluded from the backup by the .cache
# rule and by its own CACHEDIR.TAG.
CACHE_DIR=${DEVBOX_BACKUP_CACHE:-/home/dev/.cache/restic-devbox-backup}

BACKUP_PATHS=(/home/dev /workspace /etc/ssh/keys /run/secrets)

EXCLUDES=(
  # The laptop's list (dotfiles modules/restic-backup.nix), applied to each
  # home on this box: dev's own, and every synced client home under
  # /workspace. Its desktop-only entries (Steam, flatpak, Firefox, snap) are
  # dropped; nothing here matches them.
  /home/dev/.cache                /workspace/*/.cache
  /home/dev/.local/share/Trash    /workspace/*/.local/share/Trash
  /home/dev/Downloads             /workspace/*/Downloads
  node_modules target .venv __pycache__ '*.tmp'
  # This box only: package-manager caches, re-downloaded on demand (~11 GB).
  /home/dev/.npm
  /home/dev/.gradle/caches
  /home/dev/.cargo/registry
  /workspace/.pnpm-store
  /workspace/tmp
)

say() { printf '[devbox-backup] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { printf 'devbox-backup: %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" = 0 ] || die "run as root: sudo devbox-backup ${1:-}"
}

# Loads the settings and exports exactly what restic needs: the passphrase and
# a repository URL carrying the rest-server login. Nothing else from the file
# is exported, so the BACKUP_* values stay in this shell.
load_config() {
  if [ ! -r "$ENV_FILE" ]; then
    echo "devbox-backup: $ENV_FILE is missing — entrypoint.sh writes it at boot; restart the container" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  local missing=""
  [ -n "${BACKUP_RESTIC_PASSWORD:-}" ] || missing="$missing BACKUP_RESTIC_PASSWORD"
  [ -n "${BACKUP_REST_PASSWORD:-}" ] || missing="$missing BACKUP_REST_PASSWORD"
  if [ -n "$missing" ]; then
    echo "devbox-backup: not configured — set${missing} in the container template, then restart" >&2
    return 1
  fi

  local repo="${BACKUP_REPO:-rest:http://restic-rest-server-devbox:8000/}"
  case "$repo" in
    rest:http://*@*|rest:https://*@*)
      echo "devbox-backup: BACKUP_REPO must not carry credentials; they come from BACKUP_REST_USER/BACKUP_REST_PASSWORD" >&2
      return 1 ;;
    rest:http://*|rest:https://*) ;;
    *)
      echo "devbox-backup: BACKUP_REPO must be a rest:http(s):// URL, got: $repo" >&2
      return 1 ;;
  esac

  # Percent-encode the login for the URL. Values travel through the
  # environment, never argv, so they don't show up in ps.
  local enc_user enc_pw
  enc_user="$(V="${BACKUP_REST_USER:-devbox}" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["V"], safe=""))')"
  enc_pw="$(V="$BACKUP_REST_PASSWORD" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["V"], safe=""))')"

  export RESTIC_REPOSITORY="${repo%%://*}://${enc_user}:${enc_pw}@${repo#*://}"
  export RESTIC_PASSWORD="$BACKUP_RESTIC_PASSWORD"
  export RESTIC_CACHE_DIR="$CACHE_DIR"
  SNAPSHOT_HOST="${BACKUP_HOST:-devbox}"
  unset BACKUP_RESTIC_PASSWORD BACKUP_REST_PASSWORD
}

# One backup and forget. Returns restic's backup exit code: 0 complete, 3
# snapshot saved but some files unreadable, anything else no snapshot.
backup_once() {
  load_config || return 1
  mkdir -p "$CACHE_DIR"
  # Off a terminal restic prints no progress at all, so a long run (the first
  # full backup takes hours) looks hung in the log. One status line a minute.
  export RESTIC_PROGRESS_FPS=0.016666

  # Create the repo on the very first run. Exit 10 is restic's "repository
  # does not exist"; any other failure (network, wrong login) must not lead to
  # an init attempt, so it is reported as it is.
  local rc=0 out
  out="$("$RESTIC" cat config 2>&1 >/dev/null)" || rc=$?
  if [ "$rc" = 10 ]; then
    say "repository does not exist yet; initialising it"
    "$RESTIC" init
  elif [ "$rc" != 0 ]; then
    say "cannot open the repository (restic exit $rc):"
    printf '%s\n' "$out"
    return "$rc"
  fi

  local paths=() p
  for p in "${BACKUP_PATHS[@]}"; do
    if [ -e "$p" ]; then paths+=("$p"); else say "skipping $p (not present)"; fi
  done
  local exclude_args=() e
  for e in "${EXCLUDES[@]}"; do exclude_args+=(--exclude "$e"); done

  # Flags as on the laptop, plus --host: this container's hostname changes on
  # every recreate, and restic picks the parent snapshot and groups retention
  # by host. A shifting host means a full rescan and retention that never
  # applies to the old names.
  #   --stuck-request-timeout  abort and retry an HTTP request that stopped
  #                            making progress, so a half-dead connection
  #                            can't hang the run
  #   --retry-lock             wait out a lock left by an interrupted run
  # nice/ionice: this box shares the host with everything else on Unraid.
  rc=0
  nice -n 10 ionice -c2 -n7 "$RESTIC" backup \
    --verbose \
    --stuck-request-timeout 5m \
    --retry-lock 5m \
    --host "$SNAPSHOT_HOST" \
    --exclude-caches \
    "${exclude_args[@]}" \
    "${paths[@]}" || rc=$?

  case "$rc" in
    0) ;;
    3) say "snapshot saved, but some files could not be read (see above)" ;;
    *) say "backup failed (restic exit $rc); no snapshot saved"; return "$rc" ;;
  esac

  # Retention as on the laptop; the policy keeps the union. At one snapshot
  # every 10 minutes:
  #   --keep-within 3d  → every snapshot from the last 3 days (~432)
  #   --keep-daily 14   → one per day for the last 14 days
  #   --keep-weekly 8   → one per week for the last 8 weeks
  #   --keep-monthly 12 → one per month for the last 12 months
  # --group-by host (the default is host,paths): adding or removing a backup
  # path later would otherwise strand every older snapshot in a group of its
  # own, kept forever. Pruning the data is Backrest's monthly job.
  "$RESTIC" forget \
    --stuck-request-timeout 5m \
    --retry-lock 5m \
    --host "$SNAPSHOT_HOST" \
    --group-by host \
    --keep-within 3d \
    --keep-daily 14 \
    --keep-weekly 8 \
    --keep-monthly 12 \
    || say "forget failed; retention catches up on the next run"
  return "$rc"
}

# One locked, time-limited run. The lock means a manual `run` and the schedule
# never overlap; timeout's limits match the laptop's service (TimeoutStartSec
# 12h, then TimeoutStopSec 2m for restic to drop its lock before SIGKILL).
# timeout signals its whole process group, so restic gets the SIGTERM too.
locked_run() {
  mkdir -p "$STATE_DIR"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    say "another backup is still running; skipping this one"
    return 0
  fi
  local start rc=0
  start=$(date +%s)
  say "backup starting"
  timeout --kill-after=2m 12h "$0" __once || rc=$?
  [ "$rc" = 124 ] && say "backup hit the 12h limit and was stopped"
  say "backup finished: exit $rc after $(( $(date +%s) - start ))s"
  printf '%s exit=%s duration=%ss\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rc" "$(( $(date +%s) - start ))" > "$LAST_FILE"
  exec 9>&-
  return "$rc"
}

# Copy-and-truncate rather than rename: the schedule's stdout is the log file,
# opened once for appending by entrypoint.sh, and would keep writing into a
# renamed file.
rotate_log() {
  local size
  size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
  if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
    cp "$LOG" "$LOG.1" && : > "$LOG"
  fi
}

# ── run ─────────────────────────────────────────────────────────────
cmd_run() {
  need_root run
  touch "$LOG" 2>/dev/null || true
  locked_run 2>&1 | tee -a "$LOG"
}

# ── loop ────────────────────────────────────────────────────────────
# Stands in for the laptop's systemd timer (OnCalendar=*:0/10,
# RandomizedDelaySec=1m, Persistent=true). The first run comes 2 minutes after
# boot, which is the catch-up for whatever was missed while the box was down.
# After that, every :00 :10 :20 … plus up to a minute. A run that overruns a
# slot skips it, as a timer does while its service is still active.
cmd_loop() {
  need_root loop
  say "schedule started (every 10 minutes; first run in 2 minutes)"
  sleep 120
  while :; do
    rotate_log
    locked_run || true
    local now next
    now=$(date +%s)
    next=$(( now - now % 600 + 600 ))
    sleep $(( next - now + RANDOM % 60 ))
  done
}

# ── status ──────────────────────────────────────────────────────────
cmd_status() {
  need_root status
  if pgrep -f "devbox-backup loop" >/dev/null 2>&1; then
    echo "schedule: running"
  else
    echo "schedule: NOT running (BACKUP_ENABLED off, or see $LOG)"
  fi
  if [ -s "$LAST_FILE" ]; then
    echo "last run: $(cat "$LAST_FILE")"
  else
    echo "last run: none since boot"
  fi
  if [ -e "$LOCK_FILE" ] && ! flock -n "$LOCK_FILE" true 2>/dev/null; then
    echo "a backup is running now"
  fi
  echo "log: $LOG"
  echo
  load_config || exit 1
  "$RESTIC" snapshots --host "$SNAPSHOT_HOST" --latest 5 --compact
}

# ── restic ──────────────────────────────────────────────────────────
cmd_restic() {
  need_root restic
  load_config || exit 1
  exec "$RESTIC" "$@"
}

case "${1:-}" in
  run)     cmd_run ;;
  loop)    cmd_loop ;;
  status)  cmd_status ;;
  restic)  shift; cmd_restic "$@" ;;
  __once)  backup_once ;;   # internal: one unlocked run, under locked_run's timeout
  *) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
