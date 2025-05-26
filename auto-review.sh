#!/bin/bash
# Auto-review script for CLAUDE.md changes

# Check if inotifywait is installed
if ! command -v inotifywait &> /dev/null; then
    echo "Installing inotify-tools..."
    sudo apt-get update && sudo apt-get install -y inotify-tools
fi

echo "Watching CLAUDE.md for changes..."
echo "Press Ctrl+C to stop"

while true; do
    # Wait for CLAUDE.md to be modified or moved
    inotifywait -e modify,moved_to /home/peter/.claude/CLAUDE.md
    
    # Wait a second for editor to finish saving
    sleep 1
    
    # Check if there are actual git changes
    if cd /home/peter/.claude && git diff --quiet CLAUDE.md && git diff --cached --quiet CLAUDE.md; then
        echo "No git changes detected in CLAUDE.md"
    else
        echo "Changes detected! Triggering Claude review..."
        # Use claude with -p flag to run review command
        claude -p "review" --dangerously-skip-permissions
    fi
done