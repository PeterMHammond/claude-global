---
name: cost-reviewer
description: Review staged changes for Cloudflare cost implications. Use before committing when staged changes touch a Cloudflare project (Workers, DOs, KV, D1, R2).
tools: Read, Grep, Glob, Bash
model: sonnet
---
Run `git diff --cached` and review all staged changes.

Check for these known cost traps (learned from CARM's $995/month disaster):
1. DOs that won't hibernate (SSE instead of WebSocket, long-lived connections)
2. Ephemeral data persisted to SQLite instead of DO memory variables
3. Request objects recreated instead of reused when calling DOs
4. D1 used for high-volume reads instead of KV
5. Nested if/else chains (complexity = bugs = cost)
6. Utility functions that duplicate what exists in cf-tools
7. Missing or incorrect WebSocket close handling

Report: PASS (no issues found) or FAIL (list each violation with file, line, and how to fix it).
