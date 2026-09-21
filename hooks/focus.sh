#!/usr/bin/env bash
# Record this session's focus + colour; the UserPromptSubmit hook renames the session and records the colour.
set -euo pipefail
# capitalise each focus word so the badge reads as a label
title(){ printf '%s' "$1" | sed 's/\b\(.\)/\u\1/g'; }
raw="${1:?usage: focus.sh <focus words> [red|green|yellow|blue|purple|cyan]}"
focus=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '_-' '  ' | tr -cd 'a-z0-9 ' | tr -s ' ' | sed 's/^ //;s/ $//' | cut -c1-48)
[ -n "$focus" ] || { echo "empty focus" >&2; exit 1; }
color="${2:-}"
if [ -z "$color" ]; then
  case "$focus" in
    *fix*|*bug*|*debug*|*incident*) color=red ;;
    *deploy*|*ship*|*release*)      color=green ;;
    *review*|*audit*|*triage*)      color=yellow ;;
    *doc*|*write*|*plan*|*spec*)    color=blue ;;
    *test*|*mutat*|*gate*)          color=cyan ;;
    *)                              color=purple ;;
  esac
fi
sid="${CLAUDE_CODE_SESSION_ID:?no CLAUDE_CODE_SESSION_ID}"
mkdir -p "$HOME/.claude/session-focus"
printf '%s\n%s\n' "$focus" "$color" > "$HOME/.claude/session-focus/$sid"
printf '%s %s %s [%s]\n' "$(basename "$PWD")" "$(date +%Y-%m-%d)" "$(title "$focus")" "$color"
