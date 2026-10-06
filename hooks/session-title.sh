#!/usr/bin/env bash
# UserPromptSubmit: name the session "<root>-<focus>-<YYYYMMDD>", and record its colour for reopen.
set -uo pipefail
slug(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--' | tr -cd 'a-z0-9-' | tr -s '-' | sed 's/^-//;s/-$//'; }
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
f="$HOME/.claude/session-focus/$sid"
# unnamed session: nudge once per prompt until a focus is recorded, then go quiet
[ -r "$f" ] || exec jq -cn '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:"This session is unnamed. Once you know the task, run: ~/.claude/hooks/focus.sh <2-4 focus words>"}}'
line1=$(sed -n 1p "$f")
color=$(sed -n 2p "$f" | tr -cd 'a-z')
root=$(sed -n 3p "$f")
day=$(sed -n 4p "$f" | tr -cd '0-9')
mark=$(sed -n 5p "$f")   # used by the status line, never in the title
# legacy single-line files carry "<focus> <colour>"; split the trailing colour word back off
if [ -z "$color" ]; then
  case "${line1##* }" in
    red|green|yellow|blue|purple|cyan) color="${line1##* }"; line1="${line1% *}" ;;
  esac
fi
focus=$(slug "$line1" | cut -c1-48 | sed 's/-$//')
[ -n "$focus" ] || exit 0
tx=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
if [ -n "$color" ] && [ -f "$tx" ]; then
  last=$(grep -o '"agentColor":"[a-z]*"' "$tx" | tail -1 | cut -d'"' -f4)
  [ "$last" = "$color" ] || printf '{"type":"agent-color","agentColor":"%s","sessionId":"%s"}\n' "$color" "$sid" >> "$tx"
fi
# Root and date come from the focus file so the name never drifts; only pre-pin sessions fall back.
[ -n "$root" ] || root=$(slug "$(basename "$(printf '%s' "$input" | jq -r '.cwd // empty')")")
[ -n "$root" ] || root=$(slug "$(basename "$PWD")")
[ -n "$day" ] || day=$(date +%Y%m%d)
title="$root-$focus-$day"

[ "$(printf '%s' "$input" | jq -r '.session_title // empty')" = "$title" ] && exit 0
jq -cn --arg t "$title" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",sessionTitle:$t}}'
