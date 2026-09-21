#!/usr/bin/env bash
# List all installed skills

SKILLS_DIR="$HOME/.claude/skills"

if [ ! -d "$SKILLS_DIR" ]; then
    echo "No skills directory found at $SKILLS_DIR"
    exit 1
fi

echo "Installed skills:"
echo ""

for skill in "$SKILLS_DIR"/*/; do
    if [ -f "${skill}SKILL.md" ]; then
        name=$(basename "$skill")
        desc=$(grep -A1 "^description:" "${skill}SKILL.md" | tail -1 | sed 's/^description: //' | head -c 80)
        echo "  $name"
        echo "    $desc"
        echo ""
    fi
done
