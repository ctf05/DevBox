#!/usr/bin/env bash
# Create a sibling worktree under the current laptop user's
# .../.superset/worktrees/<proj>/<author>/ directory on the devbox.
#
# Detects the user prefix (e.g. /home/popper-mobile) from $PWD — never
# hardcoded — so the same image works for any laptop user. The new
# worktree lives at the laptop's $HOME path, which is what Mutagen syncs
# back to the laptop a few seconds later.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: new-worktree <branch-name>" >&2
  exit 2
fi
branch="$1"

# Must be inside .../.superset/worktrees/<proj>/<author>[/...]
if [[ "$PWD" != */.superset/worktrees/*/* ]]; then
  echo "new-worktree: must be run inside .../.superset/worktrees/<proj>/<author>/<...>" >&2
  echo "  current: $PWD" >&2
  exit 2
fi

prefix="${PWD%%/.superset/worktrees/*}"
rest="${PWD#"$prefix"/.superset/worktrees/}"
proj="${rest%%/*}"
rest="${rest#"$proj"/}"
author="${rest%%/*}"

if [[ -z "$prefix" || -z "$proj" || -z "$author" ]]; then
  echo "new-worktree: could not parse project/author from $PWD" >&2
  exit 2
fi

new_path="$prefix/.superset/worktrees/$proj/$author/$branch"
main_repo="$prefix/.superset/projects/$proj"

if [[ ! -e "$main_repo/.git" ]]; then
  echo "new-worktree: main repo not found at $main_repo" >&2
  echo "  (is the projects sync running? run 'mutagen sync list' on the laptop)" >&2
  exit 2
fi

if [[ -e "$new_path" ]]; then
  echo "new-worktree: $new_path already exists" >&2
  exit 1
fi

if git -C "$main_repo" show-ref --verify --quiet "refs/heads/$branch"; then
  echo "→ branch '$branch' exists; checking out at $new_path"
  git -C "$main_repo" worktree add "$new_path" "$branch"
else
  echo "→ creating new branch '$branch' at $new_path"
  git -C "$main_repo" worktree add -b "$branch" "$new_path"
fi

echo
echo "→ ready at: $new_path"
echo "  (same path on the laptop — Mutagen will sync it back in ~30s)"
echo "  cd: cd $new_path"
