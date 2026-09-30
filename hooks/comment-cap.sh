#!/usr/bin/env bash
# PostToolUse gate: the ≤100-char one-line comment rule, enforced at WRITE time, not commit time.
# Mirrors craft/scripts/no-overlong-comment-line.sh (craft#716) — same cap, same syntax map. Judges
# only the text this edit introduces, so a tree's pre-existing long lines never red.
set -uo pipefail
export LC_ALL=C.UTF-8
CAP=100

IN=$(cat)
FILE=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$IN")
case "$FILE" in
  *.rs|*.js|*.mjs|*.ts|*.css|*.sh|*.toml|*.yaml|*.yml|*.html) ;;
  *) case "${FILE##*/}" in *.*) exit 0 ;; esac ;;
esac

ADDED=$(jq -r '[.tool_input.content?, .tool_input.new_string?, (.tool_input.edits[]?.new_string)]
               | map(select(. != null)) | join("\n")' <<<"$IN")
[ -n "$ADDED" ] || exit 0

FOUND=$(awk -v cap="$CAP" -v file="$FILE" '
  { text = $0; sub(/^[[:space:]]+/, "", text)
    if (file ~ /\.(rs|js|mjs|ts|css)$/) comment = (text ~ /^\/\//)
    else if (file ~ /\.(sh|toml|yaml|yml)$/ || file !~ /[^\/]\.[^\/]*$/) comment = (text ~ /^#/ && text !~ /^#!/)
    else if (file ~ /\.html$/) comment = (text ~ /^(\{#|<!--)/)
    else comment = 0
    if (comment && length($0) > cap) printf "  %d chars: %s\n", length($0), substr(text, 1, 72) "…"
  }' <<<"$ADDED")

[ -z "$FOUND" ] && exit 0

{ printf '✗ comment cap — %d comment line(s) over %d chars in %s:\n' "$(wc -l <<<"$FOUND")" "$CAP" "$FILE"
  printf '%s\n' "$FOUND"
  printf 'Fix them NOW, in this turn. ONE physical line, ≤%d chars, carrying only what the code cannot\nshow. Never hand-wrap one thought across // lines. A settled ruling is a pointer to its issue.\n' "$CAP"
} >&2
exit 2
