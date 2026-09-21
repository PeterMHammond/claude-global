#!/usr/bin/env bash
# UserPromptSubmit: name the session "<folder> <YYYY-MM-DD> <Focus>", and record its colour for reopen.
set -uo pipefail
# capitalise each focus word so the badge reads as a label
title(){ printf '%s' "$1" | sed 's/\b\(.\)/\u\1/g'; }
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
f="$HOME/.claude/session-focus/$sid"
# unnamed session: nudge once per prompt until a focus is recorded, then go quiet
[ -r "$f" ] || exec jq -cn '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:"This session is unnamed. Once you know the task, run: ~/.claude/hooks/focus.sh <2-4 focus words>"}}'
line1=$(sed -n 1p "$f")
color=$(sed -n 2p "$f" | tr -cd 'a-z')
# legacy single-line files carry "<focus> <colour>"; split the trailing colour word back off
if [ -z "$color" ]; then
  case "${line1##* }" in
    red|green|yellow|blue|purple|cyan) color="${line1##* }"; line1="${line1% *}" ;;
  esac
fi
focus=$(printf '%s' "$line1" | tr '_-' '  ' | tr -cd 'a-z0-9 ' | tr -s ' ' | sed 's/^ //;s/ $//' | cut -c1-48)
[ -n "$focus" ] || exit 0
tx=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
if [ -n "$color" ] && [ -f "$tx" ]; then
  last=$(grep -o '"agentColor":"[a-z]*"' "$tx" | tail -1 | cut -d'"' -f4)
  [ "$last" = "$color" ] || printf '{"type":"agent-color","agentColor":"%s","sessionId":"%s"}\n' "$color" "$sid" >> "$tx"
fi
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
title="$(basename "${cwd:-$PWD}") $(date +%Y-%m-%d) $(title "$focus")"
[ "$(printf '%s' "$input" | jq -r '.session_title // empty')" = "$title" ] && exit 0
jq -cn --arg t "$title" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",sessionTitle:$t}}'
