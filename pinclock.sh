#!/usr/bin/env bash
# Run a command with the wall clock frozen at day resolution (midnight UTC).
#
# Why this exists: some generators read the system clock and write the result
# into a file that gets committed — drizzle-kit stamps a millisecond epoch into
# packages/db/drizzle/meta/_journal.json, and it is far from the only one.
# Neither TZ=UTC nor SOURCE_DATE_EPOCH helps there: the first only changes how
# the time is *formatted*, and the second only works for tools that opted into
# honouring it. drizzle-kit did not. The only lever that covers a tool which
# never agreed to cooperate is to change what the clock tells it.
#
#   pinclock pnpm --filter @hushbox/db db:generate
#
# The wall clock is frozen, not merely offset: every Date.now() inside the
# child returns the exact same midnight-UTC value, so the output is identical
# no matter when it ran, and re-running it produces no diff. The monotonic
# clock is deliberately left real (FAKETIME_DONT_FAKE_MONOTONIC=1) — freezing
# it too makes libuv's timers never expire, which hangs any Node process that
# calls setTimeout. That failure is silent and looks like a hung build, so it
# is worth stating plainly rather than rediscovering.
#
# Coverage: this is an LD_PRELOAD shim, so it reaches anything that reads the
# clock through libc — node, python3, coreutils, and every child they spawn
# (the preload is inherited). It CANNOT reach statically linked Go binaries,
# which issue raw syscalls and read the vDSO directly; `gh` and `lazygit` on
# this image are both static. A Go tool run under pinclock silently sees the
# real clock. There is no way to fix that from here, so don't assume coverage
# you don't have — verify the output of anything new you wrap.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  cat >&2 <<'USAGE'
usage: pinclock <command> [args...]

Runs <command> with the wall clock frozen at midnight UTC of the current day.
Override the pinned instant with SOURCE_DATE_EPOCH (a unix timestamp).
USAGE
  exit 2
fi

# Fail loudly if the shim is missing. Falling back to the real clock would let
# a generator stamp the true time into a committed file while the caller
# believes it was pinned — a silent leak is worse than a broken build.
if ! command -v faketime >/dev/null 2>&1; then
  echo "pinclock: faketime not installed — refusing to run with a live clock" >&2
  exit 127
fi

# SOURCE_DATE_EPOCH is already exported per-shell as midnight UTC (see
# config/zshenv), so honouring it here keeps one source of truth rather than
# computing the day twice and risking the two disagreeing across a midnight
# boundary. The fallback covers non-zsh callers.
epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$epoch" ]]; then
  now="$(date -u +%s)"
  epoch=$(( now - now % 86400 ))
fi

# UTC days start on exact multiples of 86400, so truncation is the whole
# calculation — no date parsing, no timezone arithmetic, no DST edge case.
epoch=$(( epoch - epoch % 86400 ))

# faketime parses an `@` timestamp in the *local* zone, so TZ must be pinned
# here or the frozen instant lands hours off midnight on a non-UTC box.
pinned="$(TZ=UTC date -u -d "@$epoch" '+%Y-%m-%d %H:%M:%S')"

# `i0` freezes the fake clock (advance 0 per call) instead of letting it tick
# forward from the pinned origin, so a slow generator can't drift into a
# later timestamp and reintroduce sub-day resolution.
exec env \
  TZ=UTC \
  FAKETIME_DONT_FAKE_MONOTONIC=1 \
  faketime -f "@${pinned} i0" \
  "$@"
