#!/usr/bin/env bash
# Status line: <mark> <cwd> [branch] ................ <model>. The session's mark and focus live here,
# never in the session title — the title has to stay one double-clickable token.
set -uo pipefail
input=$(cat)
j(){ printf '%s' "$input" | jq -r "$1 // empty"; }
model=$(j '.model.display_name')
used=$(j '.context_window.used_percentage')
ctx=""; [ -n "$used" ] && ctx=$(printf 'ctx %.0f%%  ' "$used")
cwd=$(j '.workspace.current_dir'); cwd="${cwd:-$PWD}"
sid=$(j '.session_id')
mark=""; focus=""
f="$HOME/.claude/session-focus/$sid"
if [ -n "$sid" ] && [ -r "$f" ]; then
  focus=$(sed -n 1p "$f")
  mark=$(sed -n 5p "$f")
fi
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  [ -n "$branch" ] && left=$(printf '%s [%s]' "$cwd" "$branch") || left="$cwd"
else
  left="$cwd"
fi
[ -n "$mark" ] && left="$mark $left"
[ -n "$focus" ] && left="$left · $focus"
width="${COLUMNS:-$(tput cols 2>/dev/null)}"; width="${width:-80}"; width=$((width - 6))
# Count display columns, not bytes, so the emoji and the middle dot do not skew the padding.
lw=$(printf '%s' "$left" | python3 -c 'import sys,unicodedata;s=sys.stdin.read();print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s))' 2>/dev/null || printf '%s' "${#left}")
pad=$((width - lw - ${#ctx} - ${#model})); [ "$pad" -lt 1 ] && pad=1
printf '%s%*s\033[32m%s\033[38;5;208m%s\033[0m' "$left" "$pad" "" "$ctx" "$model"
