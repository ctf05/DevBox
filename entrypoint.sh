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
for var in GITHUB_PERSONAL_ACCESS_TOKEN; do
  val="${!var:-}"
  [ -n "$val" ] && printf 'export %s=%q\n' "$var" "$val" >> "$RUNTIME_ENV"
done
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
if [ ! -S /var/run/docker.sock ]; then
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

exec /usr/sbin/sshd -D -e
