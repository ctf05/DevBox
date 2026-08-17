#!/usr/bin/env bash
# Normalise file modification times to midnight UTC of the current day.
#
# Git does not record mtimes, so this is not about the commit itself. It
# matters for anything that packs a file into an archive — tar, zip, jar,
# .xcodeproj bundles — because those formats *do* record mtimes, and a
# committed archive carries the real minute its contents were written.
#
#   scrub-mtimes                 # git-tracked files in the current repo
#   scrub-mtimes path/ other/    # those paths, tracked or not
#
# Only files newer than the target are touched, so this never drags an old
# file forward and never rewrites a tree that is already clean.
#
# Note the ceiling: mtime and atime are settable, ctime is not. The kernel
# stamps ctime on every inode change and userspace cannot override it, so
# local forensic timing survives this. That is fine for the threat model —
# ctime does not travel through git, tar, or any published artifact — but it
# does mean this is a publication-time scrub, not an on-disk guarantee.
set -euo pipefail

epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$epoch" ]]; then
  now="$(date -u +%s)"
  epoch=$(( now - now % 86400 ))
fi
epoch=$(( epoch - epoch % 86400 ))

stamp="$(date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ')"

count=0

touch_if_newer() {
  # -newermt compares against the target instant, so files already at or
  # before midnight are left alone and repeat runs are no-ops.
  if [[ -f "$1" || -d "$1" ]] && [[ -n "$(find "$1" -maxdepth 0 -newermt "@$epoch" 2>/dev/null)" ]]; then
    touch -h -d "$stamp" "$1" 2>/dev/null && count=$(( count + 1 ))
  fi
}

if [[ $# -gt 0 ]]; then
  # Explicit paths: sweep them recursively, still skipping git internals.
  while IFS= read -r -d '' f; do
    touch_if_newer "$f"
  done < <(find "$@" -name .git -prune -o \( -type f -o -type d \) -newermt "@$epoch" -print0 2>/dev/null)
else
  # Default: git-tracked files only. This is both the precise set (untracked
  # build output and node_modules are never published) and the fast one — no
  # walk of a monorepo's dependency tree.
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "scrub-mtimes: not inside a git repository; pass explicit paths instead" >&2
    exit 2
  fi
  root="$(git rev-parse --show-toplevel)"
  while IFS= read -r -d '' f; do
    touch_if_newer "$root/$f"
  done < <(git -C "$root" ls-files -z)
fi

echo "scrub-mtimes: normalised $count path(s) to $stamp" >&2
