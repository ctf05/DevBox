#!/usr/bin/env bash
set -euo pipefail

# Grow /dev/shm for headless browsers. Docker's 64 MB default starves parallel
# Chromium renderers (crashes surface as "Page crashed" / "Target closed").
# The container runs --privileged, so an in-place remount is permitted; if it
# isn't (non-privileged run), keep the default and continue.
mount -o remount,size=2g /dev/shm || echo "entrypoint: /dev/shm remount skipped (needs --privileged)" >&2

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
# is additive — new fields the image ships (e.g. statusLine) still need
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

# Timezone
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

# Bridge selected container env vars into SSH sessions. sshd doesn't pass its
# own environment to login shells, so vars set via `docker run -e` (Unraid
# "Variable" entries) never reach interactive shells or the tools launched from
# them (git, gh, claude). Write them to a file /etc/zsh/zshenv sources for every
# zsh invocation. Rewritten from scratch each boot so a removed var doesn't linger.
RUNTIME_ENV=/etc/zsh/env.runtime
: > "$RUNTIME_ENV"
for var in GITHUB_PERSONAL_ACCESS_TOKEN FAL_KEY; do
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

# ── Headroom: route Claude Code through the local compression proxy ─
# On by default. Disable per-container with HEADROOM_ENABLED=0 (also accepts
# false/no/off). The proxy forwards Claude Code's existing OAuth token
# untouched (subscription "stealth" mode), so no API key is needed. It runs
# as `dev` so stats (~/.headroom/proxy_savings.json) and the perf log
# (~/.headroom/logs/proxy.log) live under the dev user's home.
#
# Fail-safe: Claude is routed (via env.ANTHROPIC_BASE_URL in settings.json)
# ONLY after the proxy answers /health. If it never comes up, routing is left
# off so `claude` keeps working in normal direct mode instead of breaking.
HEADROOM_PORT="${HEADROOM_PORT:-8787}"
case "${HEADROOM_ENABLED:-1}" in
  0|false|False|FALSE|no|No|NO|off|Off|OFF) headroom_on=0 ;;
  *) headroom_on=1 ;;
esac

# Add (mode=on) or remove (mode=off) Headroom's two env keys in the dev user's
# ~/.claude/settings.json. Claude Code reads settings at session start, so this
# governs every new `claude` session; user-set keys on .env are preserved.
hr_route() {  # $1 = on|off
  local mode="$1"
  runuser -u dev -- env HOME=/home/dev hr_mode="$mode" hr_port="$HEADROOM_PORT" bash -c '
    f="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    [ -s "$f" ] || printf "{}\n" > "$f"
    tmp="$(mktemp)" || exit 0
    if [ "$hr_mode" = on ]; then
      jq --arg url "http://127.0.0.1:$hr_port" \
         ".env = ((.env // {}) + {ANTHROPIC_BASE_URL: \$url, ENABLE_TOOL_SEARCH: \"true\"})" \
         "$f" > "$tmp" && mv "$tmp" "$f" || rm -f "$tmp"
    else
      jq "if has(\"env\") then .env |= (del(.ANTHROPIC_BASE_URL) | del(.ENABLE_TOOL_SEARCH)) else . end
          | if (has(\"env\") and ((.env | length) == 0)) then del(.env) else . end" \
         "$f" > "$tmp" && mv "$tmp" "$f" || rm -f "$tmp"
    fi
  ' || echo "entrypoint: headroom settings update ($mode) failed" >&2
}

if [ "$headroom_on" = 1 ]; then
  touch /var/log/headroom.log && chown dev:dev /var/log/headroom.log || true

  # Register the headroom_retrieve MCP tool (idempotent; proxy need not be up).
  runuser -u dev -- env HOME=/home/dev PATH=/usr/local/bin:/usr/bin:/bin \
    headroom mcp install --agent claude --proxy-url "http://127.0.0.1:${HEADROOM_PORT}" \
    >> /var/log/headroom.log 2>&1 || echo "entrypoint: headroom mcp install failed (non-fatal)" >&2

  # Proxy under a respawn loop (mirrors the dockerd pattern below/above), run as
  # dev. HEADROOM_UPDATE_CHECK=off avoids the daily PyPI version ping.
  (
    while :; do
      printf '[entrypoint] starting headroom proxy at %s\n' "$(date -Iseconds)"
      runuser -u dev -- env HOME=/home/dev PATH=/usr/local/bin:/usr/bin:/bin \
        HEADROOM_UPDATE_CHECK=off headroom proxy --port "$HEADROOM_PORT" || true
      printf '[entrypoint] headroom proxy exited at %s; restarting in 3s\n' "$(date -Iseconds)"
      sleep 3
    done
  ) >> /var/log/headroom.log 2>&1 &

  # Enable Claude routing once /health passes (backgrounded so it never blocks
  # boot). First boot may take a while: it downloads the ~261MB ONNX text model.
  (
    ready=0
    for _ in $(seq 1 120); do
      if curl -fsS "http://127.0.0.1:${HEADROOM_PORT}/health" >/dev/null 2>&1; then
        ready=1; break
      fi
      sleep 1
    done
    if [ "$ready" = 1 ]; then
      hr_route on
      printf '[entrypoint] headroom proxy ready; Claude Code routed via 127.0.0.1:%s\n' \
        "$HEADROOM_PORT" >> /var/log/headroom.log
    else
      hr_route off
      printf '[entrypoint] WARNING: headroom proxy not ready in 120s; Claude left in direct mode\n' \
        >> /var/log/headroom.log
      echo "entrypoint: headroom proxy did not come up in 120s — Claude not routed; see /var/log/headroom.log" >&2
    fi
  ) &
else
  # Explicitly disabled — strip any prior routing so `claude` runs direct.
  hr_route off
  echo "entrypoint: Headroom disabled (HEADROOM_ENABLED=${HEADROOM_ENABLED:-})" >&2
fi

exec /usr/sbin/sshd -D -e
