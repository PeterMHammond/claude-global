#!/usr/bin/env bash
# Fetch latest Anthropic skill documentation
# Run before creating any skill to get current best practices

echo "=== Anthropic Skill Best Practices ==="
echo ""
curl -sL "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices" 2>/dev/null | head -500

echo ""
echo "=== Claude Code Skills Docs ==="
echo ""
curl -sL "https://code.claude.com/docs/en/skills" 2>/dev/null | head -500
