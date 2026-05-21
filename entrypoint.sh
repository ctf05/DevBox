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

# authorized_keys from env var
mkdir -p /home/dev/.ssh
if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
  printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /home/dev/.ssh/authorized_keys
fi
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

exec /usr/sbin/sshd -D -e
