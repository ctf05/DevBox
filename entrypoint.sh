#!/usr/bin/env bash
set -euo pipefail

# ── Memory pressure: who dies first ────────────────────────────────
# This box can drive the host out of RAM. When that happens something has to be
# killed — by earlyoom (below) or, as the backstop, the kernel OOM killer that
# host/unraid-memory-guard.sh arms — and both pick by oom_score_adj:
#
#   +1000  commands agents run (tests, linters, builds, browsers) — set in
#          /etc/zsh/zshenv for any shell carrying CLAUDECODE
#    +300  everything else in this box: Claude sessions, tmux, shells, Mutagen,
#          dockerd and the daemons below. Set here and inherited; sshd saves
#          this value at startup and restores it in every session it forks.
#       0  the host — Unraid itself, VMs, other containers (and containers run
#          inside this box: runc sets them to 0 explicitly)
#   -1000  sshd, PID 1 — OpenSSH applies that to itself
#
# So agent commands go first, then this box, and the host last.
echo 300 > /proc/self/oom_score_adj \
  || echo "entrypoint: could not set oom_score_adj — OOM kills will not prefer this box" >&2

# Grow /dev/shm for headless browsers. Docker's 64 MB default starves parallel
# Chromium renderers (crashes surface as "Page crashed" / "Target closed").
# The container runs --privileged, so an in-place remount is permitted; if it
# isn't (non-privileged run), keep the default and continue.
mount -o remount,size=12g /dev/shm || echo "entrypoint: /dev/shm remount skipped (needs --privileged)" >&2

# Grant the dev user access to the passed-through GPU so headless browsers can
# use the iGPU. The render node is world-accessible, but card0 isn't, and its
# group id is host-defined — resolve it at runtime rather than hardcoding.
# Fully best-effort: absent device or odd gids must not block boot.
if [ -e /dev/dri/renderD128 ]; then
  gpu_gid="$(stat -c %g /dev/dri/renderD128)"
  getent group "$gpu_gid" >/dev/null 2>&1 || groupadd -g "$gpu_gid" render-host || true
  gpu_group="$(getent group "$gpu_gid" | cut -d: -f1 || true)"
  [ -n "$gpu_group" ] && usermod -aG "$gpu_group" dev || true
fi

# Persistent SSH host keys (survive image rebuilds)
HOST_KEYS=/etc/ssh/keys
mkdir -p "$HOST_KEYS"
if [ ! -f "$HOST_KEYS/ssh_host_ed25519_key" ]; then
  ssh-keygen -t ed25519 -f "$HOST_KEYS/ssh_host_ed25519_key" -N ""
  ssh-keygen -t rsa -b 4096 -f "$HOST_KEYS/ssh_host_rsa_key" -N ""
fi
chmod 600 "$HOST_KEYS"/*_key
chmod 644 "$HOST_KEYS"/*.pub

# Seed /home/dev from /etc/skel-dev on every boot.
# `cp -an` is no-clobber + recursive — adds any files the image now ships
# without touching the user's existing customizations (Claude Code creds,
# shell history, atuin DB, etc).
cp -an /etc/skel-dev/. /home/dev/ 2>/dev/null || true

# Deep-merge .claude/settings.json from skel into the user's existing
# file. `cp -an` above skips files that already exist, but settings.json
# is additive — new fields the image ships still need
# to land alongside the user's prior customizations. User values win on
# overlapping keys; new skel keys fill in the gaps.
SKEL_SETTINGS=/etc/skel-dev/.claude/settings.json
USER_SETTINGS=/home/dev/.claude/settings.json
if [ -f "$SKEL_SETTINGS" ] && [ -f "$USER_SETTINGS" ]; then
  tmp=$(mktemp)
  if jq -s '.[0] * .[1]' "$SKEL_SETTINGS" "$USER_SETTINGS" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$USER_SETTINGS"
  else
    rm -f "$tmp"
  fi
fi

# Sweep retired env keys out of the user's settings.json.
#
# The merge above can only ever ADD: user values win on overlapping keys, so
# dropping a key from the image's settings leaves the old one live in
# /home/dev forever. That is not cosmetic — ANTHROPIC_BASE_URL outlived the
# headroom proxy it pointed at (127.0.0.1:8787), and with nothing listening
# there every `claude` in the box hung on its first API call with no error
# printed. A tool removed from the image has to be unconfigured here too.
#
# Add a key here when the service behind it leaves the image; drop it again
# once no live container can still be carrying it.
RETIRED_ENV_KEYS='ANTHROPIC_BASE_URL'
if [ -f "$USER_SETTINGS" ]; then
  tmp=$(mktemp)
  if jq --arg keys "$RETIRED_ENV_KEYS" \
       'if has("env") then .env |= delpaths([$keys | split(" ") | .[] | [.]]) else . end' \
       "$USER_SETTINGS" > "$tmp" 2>/dev/null; then
    cmp -s "$tmp" "$USER_SETTINGS" || echo "entrypoint: cleared retired env keys ($RETIRED_ENV_KEYS) from settings.json" >&2
    mv "$tmp" "$USER_SETTINGS"
  else
    rm -f "$tmp"
    echo "entrypoint: retired-env-key sweep failed; settings.json left as-is" >&2
  fi
fi

# authorized_keys from env var (keys separated by `|`)
mkdir -p /home/dev/.ssh
if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
  printf '%s' "$SSH_AUTHORIZED_KEYS" | tr '|' '\n' > /home/dev/.ssh/authorized_keys
fi
chown -R dev:dev /home/dev/.ssh
chmod 700 /home/dev/.ssh
[ -f /home/dev/.ssh/authorized_keys ] && chmod 600 /home/dev/.ssh/authorized_keys

# Mounted git SSH key (private)
if [ -f /run/secrets/git_ed25519 ]; then
  install -m 600 -o dev -g dev /run/secrets/git_ed25519 /home/dev/.ssh/id_ed25519
fi

# Timezone — forced to UTC, deliberately not configurable.
#
# A local zone stamps a recoverable offset onto every timestamp this box
# emits (git dates, log lines, generated files), which pins the operator to a
# geography. UTC is therefore a fixed part of the image's posture rather than
# a per-container preference, and an inherited `-e TZ=...` from the host's
# container config is overridden rather than honoured.
#
# The override is announced rather than applied silently: a setting that
# quietly ignores what the operator asked for is the kind of surprise that
# costs an hour to diagnose later.
if [ -n "${TZ:-}" ] && [ "$TZ" != "UTC" ]; then
  echo "entrypoint: ignoring inherited TZ=$TZ — this image pins UTC (privacy posture)" >&2
fi
export TZ=UTC
ln -snf /usr/share/zoneinfo/UTC /etc/localtime
echo UTC > /etc/timezone

# Bridge selected container env vars into SSH sessions. sshd doesn't pass its
# own environment to login shells, so vars set via `docker run -e` (Unraid
# "Variable" entries) never reach interactive shells or the tools launched from
# them (git, gh, claude). Write them to a file /etc/zsh/zshenv sources for every
# zsh invocation. Rewritten from scratch each boot so a removed var doesn't linger.
RUNTIME_ENV=/etc/zsh/env.runtime
: > "$RUNTIME_ENV"
for var in GITHUB_PERSONAL_ACCESS_TOKEN FAL_KEY KEYROUTER_TOKEN; do
  val="${!var:-}"
  [ -n "$val" ] && printf 'export %s=%q\n' "$var" "$val" >> "$RUNTIME_ENV"
done
# Map the PAT to GH_TOKEN so the `gh` CLI authenticates as the same account
# (ctf05) with no separate `gh auth login`. git authenticates via the
# github.com credential helper in /etc/gitconfig, which reads the PAT directly.
if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
  printf 'export GH_TOKEN=%q\n' "$GITHUB_PERSONAL_ACCESS_TOKEN" >> "$RUNTIME_ENV"
fi
chown dev:dev "$RUNTIME_ENV"
chmod 600 "$RUNTIME_ENV"

chown -R dev:dev /home/dev

# Ensure the bind-mounted /workspace is owned by `dev` so Mutagen syncs
# from the laptop can write through the SSH user. Top-level only — don't
# recurse, both to keep boot fast and to leave existing per-project trees
# alone (their content already has correct ownership from prior writes).
mkdir -p /workspace
chown dev:dev /workspace

# Start the Docker daemon so `docker` works out of the box, the same way
# it would on a normal machine. Skipped if the host's docker.sock is
# bind-mounted in (docker-out-of-docker mode) — in that case the existing
# socket is the host daemon and we shouldn't start a second one.
# Requires the container to be run with --privileged.
#
# The gate probes for a LIVE daemon, not for a socket file. A file test is
# wrong after an unclean stop: the socket inode survives in the container
# filesystem, so the gate reads "daemon present", skips startup, and leaves
# Docker dead for the whole boot with no respawn loop to recover it — the
# state that has to be fixed by hand every time. Worse, it is self-
# perpetuating: a broken stack invites whoever finds it to repair Docker by
# hand, and concurrent hand-repair of one daemon is how this box gets wedged.
# A live host socket still answers here, so docker-out-of-docker is unchanged.
if ! docker -H unix:///var/run/docker.sock info >/dev/null 2>&1; then
  # dockerd refuses to bind over a leftover socket, so a stale one must go
  # before the loop starts. Harmless when the path is already absent.
  rm -f /var/run/docker.sock
  mkdir -p /var/log /var/lib/docker

  # Respawn loop: a single dockerd crash used to wedge the container's Docker
  # for the rest of the boot. Looping in a backgrounded subshell means transient
  # failures self-heal; the 3s sleep keeps a permanently-broken daemon (e.g.
  # /var/lib/docker landed on overlay-on-overlay) from spinning hot.
  (
    while :; do
      printf '[entrypoint] starting dockerd at %s\n' "$(date -Iseconds)"
      dockerd || true
      printf '[entrypoint] dockerd exited at %s; restarting in 3s\n' "$(date -Iseconds)"
      sleep 3
    done
  ) >> /var/log/dockerd.log 2>&1 &

  # Block until the socket accepts connections so SSH sessions don't race the
  # daemon. ~30s ceiling; surface the outcome in both /var/log/dockerd.log and
  # container stderr (visible via `docker logs`) so a broken setup is obvious
  # without having to exec in and dig.
  ready=0
  for _ in $(seq 1 60); do
    if [ -S /var/run/docker.sock ] && docker -H unix:///var/run/docker.sock info >/dev/null 2>&1; then
      ready=1; break
    fi
    sleep 0.5
  done
  if [ "$ready" = 1 ]; then
    printf '[entrypoint] dockerd ready at %s\n' "$(date -Iseconds)" >> /var/log/dockerd.log
  else
    printf '[entrypoint] WARNING: dockerd did not come up within 30s\n' >> /var/log/dockerd.log
    echo "entrypoint: dockerd did not come up within 30s — see /var/log/dockerd.log" >&2
  fi
fi

# ── claude-swap: rotate Claude Code across accounts before limits ──
# On by default. Disable per-container with CSWAP_ENABLED=0 (also accepts
# false/no/off). Accounts are added once by hand (`/login` in claude, then
# `cswap add`) and persist under /home/dev/.local/share/claude-swap.
#
# Policy is re-asserted every boot so the container env is the single source of
# truth — `cswap config set` by hand is overwritten on restart, the same way an
# inherited TZ is. It is written to cswap's settings.json rather than passed as
# flags so the dashboard and manual `cswap switch` see the same policy:
#   CSWAP_THRESHOLD  switch when the active account's binding 5h/7d window
#                    reaches this pct (default 98; 99 left too little margin
#                    for many parallel sessions between ~60s usage polls)
#   CSWAP_STRATEGY   consume-first (default) burns the account whose weekly
#                    window resets soonest; best picks the most headroom
#   CSWAP_MODEL      optional per-model weekly limits to fold in (e.g. Opus)
#
# Don't also enable auto-switch inside the cswap dashboard: the state lock keeps
# two engines from corrupting anything, but they double the polling against
# the per-account usage-endpoint budget.
CSWAP_THRESHOLD="${CSWAP_THRESHOLD:-98}"
CSWAP_STRATEGY="${CSWAP_STRATEGY:-consume-first}"
case "${CSWAP_ENABLED:-1}" in
  0|false|False|FALSE|no|No|NO|off|Off|OFF) cswap_on=0 ;;
  *) cswap_on=1 ;;
esac

cswap_dev() {
  runuser -u dev -- env HOME=/home/dev PATH=/usr/local/bin:/usr/bin:/bin cswap "$@"
}

if [ "$cswap_on" = 1 ]; then
  touch /var/log/cswap.log && chown dev:dev /var/log/cswap.log || true

  {
    cswap_dev config set autoswitch.threshold "$CSWAP_THRESHOLD" \
      && cswap_dev config set autoswitch.strategy "$CSWAP_STRATEGY" \
      && if [ -n "${CSWAP_MODEL:-}" ]; then
           cswap_dev config set autoswitch.model "$CSWAP_MODEL"
         else
           cswap_dev config unset autoswitch.model
         fi
  } >> /var/log/cswap.log 2>&1 \
    || echo "entrypoint: cswap config failed — auto-switch runs on prior settings; see /var/log/cswap.log" >&2

  # Engine under a respawn loop, run as dev. With no accounts added yet it
  # idles (polling, logging no-active-account) rather than exiting, so it
  # starts switching on its own once accounts exist. The 60s restart delay
  # (vs 3s for dockerd) keeps a persistently failing engine from
  # flooding the log; SIGTERM is handled by cswap itself.
  (
    while :; do
      printf '[entrypoint] starting cswap auto at %s (threshold %s%%, %s)\n' \
        "$(date -Iseconds)" "$CSWAP_THRESHOLD" "$CSWAP_STRATEGY"
      cswap_dev auto --json || true
      printf '[entrypoint] cswap auto exited at %s; restarting in 60s\n' "$(date -Iseconds)"
      sleep 60
    done
  ) >> /var/log/cswap.log 2>&1 &
else
  echo "entrypoint: claude-swap auto-switch disabled (CSWAP_ENABLED=${CSWAP_ENABLED:-})" >&2
fi

# ── keyrouter: one API endpoint over several Anthropic org keys ────
# Starts only when at least one KEYROUTER_KEY_<n> is set (Unraid "Variable"
# entries, one per Max plan's Console org). Apps reach it with
# ANTHROPIC_BASE_URL=$KEYROUTER_URL and ANTHROPIC_API_KEY=$KEYROUTER_TOKEN.
#
# The real keys reach only this process: they are deliberately NOT bridged into
# env.runtime, and neither is ANTHROPIC_BASE_URL or ANTHROPIC_API_KEY — an
# exported ANTHROPIC_API_KEY makes Claude Code bill the API instead of the
# subscription, and the plan credits don't cover Claude Code anyway. Only the
# client token and the URL reach shells. With KEYROUTER_TOKEN set the proxy
# listens on all interfaces (so containers started inside this box can reach it
# at the docker0 gateway); without one it stays on loopback.
KEYROUTER_PORT="${KEYROUTER_PORT:-4000}"
if compgen -e | grep -qE '^KEYROUTER_KEY_[0-9]+$'; then
  touch /var/log/keyrouter.log && chown dev:dev /var/log/keyrouter.log || true
  printf 'export KEYROUTER_URL=%q\n' "http://127.0.0.1:${KEYROUTER_PORT}" >> "$RUNTIME_ENV"

  (
    while :; do
      runuser -u dev -- env HOME=/home/dev PATH=/usr/local/bin:/usr/bin:/bin \
        KEYROUTER_PORT="$KEYROUTER_PORT" keyrouter || true
      printf '[entrypoint] keyrouter exited at %s; restarting in 3s\n' "$(date -Iseconds)"
      sleep 3
    done
  ) >> /var/log/keyrouter.log 2>&1 &
fi

# ── earlyoom: end the agent command, not the session ──────────────
# Kills before the host runs short, and only what agents ran. On by default;
# EARLYOOM_ENABLED=0 (also false/no/off) disables it.
#
# /proc/meminfo here is the host's, so the thresholds are host-wide: SIGTERM at
# 2 GiB available, SIGKILL at 1 GiB — about 1.5% of a 128 GiB host, so nearly
# everything is usable first. `-s 100` takes swap out of the decision: zram
# lives in RAM and already shows up as lost MemAvailable, so it gets used to the
# full before anything dies. The process namespace means only this box's
# processes are ever candidates; the host's are invisible from here.
#
# The victim is the highest oom_score, i.e. the largest process of an agent
# command (+1000, see the top of this file) — a browser, a test worker — and
# the next-largest after that, one at a time, until memory recovers. --ignore
# makes sessions and infrastructure untouchable outright; if they are all that
# is left, earlyoom does nothing and the kernel's OOM killer is the backstop.
#
# No -g (kill the victim's whole process group), deliberately: --ignore only
# stops a process being chosen, not being in the chosen one's group, and
# Claude Code starts MCP servers in its own group — so one oversized MCP server
# would take its session down with it.
case "${EARLYOOM_ENABLED:-1}" in
  0|false|False|FALSE|no|No|NO|off|Off|OFF) earlyoom_on=0 ;;
  *) earlyoom_on=1 ;;
esac

if [ "$earlyoom_on" = 1 ]; then
  (
    while :; do
      printf '[entrypoint] starting earlyoom at %s\n' "$(date -Iseconds)"
      earlyoom -M 2097152,1048576 -s 100,100 -p -r 3600 \
        --ignore '^(sshd|sshd-session|tmux.*|zsh|bash|claude|mutagen-agent|ttyguard|dockerd|containerd.*|runc|docker-proxy|runuser|sleep|cswap|keyrouter|earlyoom)$' \
        || true
      printf '[entrypoint] earlyoom exited at %s; restarting in 3s\n' "$(date -Iseconds)"
      sleep 3
    done
  ) >> /var/log/earlyoom.log 2>&1 &
else
  echo "entrypoint: earlyoom disabled (EARLYOOM_ENABLED=${EARLYOOM_ENABLED:-})" >&2
fi

exec /usr/sbin/sshd -D -e
