#!/usr/bin/env bash
# Claude Code statusline — neon themed.
# Reads a JSON blob from stdin (provided by Claude Code on every refresh)
# and prints one line of text. Runs every ~300ms; must be fast.
set -u

input="$(cat)"

# Neon 24-bit ANSI helpers.
ANSI_OFF=$'\e[0m'
fg() { printf '\e[38;2;%s;%s;%sm' "$1" "$2" "$3"; }
PINK=$(fg 255 86 211)
RED=$(fg 255 61 127)
ORANGE=$(fg 255 181 46)
YELLOW=$(fg 255 225 0)
GREEN=$(fg 125 255 62)
CYAN=$(fg 13 255 248)
PURPLE=$(fg 199 107 255)

# ── Parse fields ───────────────────────────────────────────────────
model=$(jq -r '.model.display_name // "Claude"' <<<"$input")
cwd=$(jq -r '.workspace.current_dir // .cwd // "?"' <<<"$input")
added=$(jq -r '.cost.total_lines_added // 0' <<<"$input")
removed=$(jq -r '.cost.total_lines_removed // 0' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")

# ── Pretty cwd (collapse $HOME, trim deep paths) ───────────────────
short_cwd="${cwd/#$HOME/\~}"
if (( ${#short_cwd} > 32 )); then
  short_cwd=$(awk -F/ '{
    n = NF
    if (n >= 2) print "…/" $(n-1) "/" $n
    else        print $0
  }' <<<"$short_cwd")
fi

# ── Git ─────────────────────────────────────────────────────────────
git_segment=""
if branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  if [[ -n $(git -C "$cwd" status --porcelain 2>/dev/null | head -1) ]]; then
    git_segment="  ${RED} ${PINK}${branch}${RED}*${ANSI_OFF}"
  else
    git_segment="  ${PINK} ${branch}${ANSI_OFF}"
  fi
fi

# ── Context usage ──────────────────────────────────────────────────
# Reads the transcript JSONL, grabs the last assistant message with a
# usage block, sums input + cache_read + cache_creation tokens.
# Context limit is sniffed from the model name (1M variant vs 200K).
ctx_segment=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  last_usage=$(grep -a '"usage"' "$transcript" 2>/dev/null | tail -1)
  if [[ -n "$last_usage" ]]; then
    used=$(jq -r '
      (.message.usage.input_tokens // 0) +
      (.message.usage.cache_read_input_tokens // 0) +
      (.message.usage.cache_creation_input_tokens // 0)
    ' <<<"$last_usage")
    if [[ "$model" == *"1M"* || "$model" == *"1m"* ]]; then
      limit=1000000
    else
      limit=200000
    fi
    pct=$(awk -v u="$used" -v l="$limit" 'BEGIN{printf "%d", (u/l)*100}')
    # Color tier
    if   (( pct < 50 )); then ctx_color="$GREEN"
    elif (( pct < 80 )); then ctx_color="$YELLOW"
    else                      ctx_color="$RED"
    fi
    # Compact token count
    if   (( used >= 1000000 )); then used_fmt=$(awk -v u="$used" 'BEGIN{printf "%.2fM", u/1000000}')
    elif (( used >= 1000    )); then used_fmt=$(awk -v u="$used" 'BEGIN{printf "%.1fk", u/1000}')
    else                              used_fmt="$used"
    fi
    if   (( limit >= 1000000 )); then limit_fmt=$(awk -v l="$limit" 'BEGIN{printf "%dM", l/1000000}')
    else                              limit_fmt=$(awk -v l="$limit" 'BEGIN{printf "%dK", l/1000}')
    fi
    ctx_segment="  ${ctx_color}${used_fmt}/${limit_fmt} ${pct}%${ANSI_OFF}"
  fi
fi

# ── Diff segment (only show if any changes) ────────────────────────
diff_segment=""
if (( added > 0 || removed > 0 )); then
  diff_segment="  ${GREEN}+${added}${ANSI_OFF} ${RED}-${removed}${ANSI_OFF}"
fi

# ── Compose ────────────────────────────────────────────────────────
printf "${CYAN}%s${ANSI_OFF}  ${PURPLE}%s${ANSI_OFF}%s%s%s\n" \
  "$model" "$short_cwd" "$git_segment" "$ctx_segment" "$diff_segment"
