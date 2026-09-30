#!/usr/bin/env bash
# PreToolUse(Bash) gate: refuses a `git add`/`git commit` whose diff adds a comment line over the cap.
# Catches sed/heredoc writes the Write|Edit hook never sees, seconds before the repo's slow gates.
set -uo pipefail
export LC_ALL=C.UTF-8
CAP=100

IN=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$IN")
grep -qE 'git( +-C +[^ ]+)? +(add|commit)' <<<"$CMD" || exit 0

CWD=$(jq -r '.cwd // empty' <<<"$IN")
DIRS=$({ echo "$CWD"
         grep -oE '(^|[;&(] *)cd +[^;&|)]+' <<<"$CMD" | sed -E 's/^[;&( ]*cd +//; s/[[:space:]]+$//; s/^["'"'"']//; s/["'"'"']$//'
         grep -oE 'git +-C +[^ ]+' <<<"$CMD" | awk '{print $3}'
       } | while read -r d; do [ -d "$d" ] && git -C "$d" rev-parse --show-toplevel 2>/dev/null; done | sort -u)
[ -n "$DIRS" ] || exit 0

FOUND=$(for R in $DIRS; do cd "$R" || continue; { git diff HEAD -U0 -M --no-color 2>/dev/null
          git ls-files -o --exclude-standard -z | xargs -0 -r -n1 git diff --no-index -U0 --no-color /dev/null 2>/dev/null
        } | awk -v cap="$CAP" '
  /^\+\+\+ / { f = $0; sub(/^\+\+\+ (b\/)?/, "", f); next }
  /^@@ /     { split($3, a, ","); n = substr(a[1], 2) + 0; next }
  /^\+/ { line = substr($0, 2); text = line; sub(/^[[:space:]]+/, "", text)
    base = f; sub(/.*\//, "", base)
    if (f ~ /\.(rs|js|mjs|ts|css)$/) c = (text ~ /^\/\//)
    else if (f ~ /\.(sh|bash|toml|yaml|yml)$/ || base !~ /\./) c = (text ~ /^#/ && text !~ /^#!/)
    else if (f ~ /\.html$/) c = (text ~ /^(\{#|<!--)/)
    else c = 0
    if (c && length(line) > cap) printf "  %s:%d (%d chars)\n", f, n, length(line)
    n++ }'; done)

[ -z "$FOUND" ] && exit 0
{ printf '✗ comment cap — added comment line(s) over %d chars; nothing was run:\n%s\n' "$CAP" "$FOUND"
  printf 'Fix them NOW: ONE physical line, ≤%d chars, then retry the same command.\n' "$CAP"
} >&2
exit 2
