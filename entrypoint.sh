#!/usr/bin/env bash
set -euo pipefail

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
  mkdir -p /var/log
  dockerd > /var/log/dockerd.log 2>&1 &

  # Block until the socket is accepting connections so SSH sessions don't
  # race the daemon's boot. ~30s ceiling — if dockerd hasn't come up by
  # then it's not going to, so we let sshd start anyway and surface the
  # state via /var/log/dockerd.log rather than wedging the container.
  for _ in $(seq 1 60); do
    [ -S /var/run/docker.sock ] && docker -H unix:///var/run/docker.sock info >/dev/null 2>&1 && break
    sleep 0.5
  done
fi

exec /usr/sbin/sshd -D -e
