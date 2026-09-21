---
name: project-usage
description: Aggregate Claude Code session usage from local JSONL transcripts (~/.claude/projects/**/*.jsonl) into a project × day cost matrix with totals and a by-model summary. Triggers on /project-usage, "show today's usage", "how much did I spend on Claude today", "claude usage by project", "weekly token report", or any request to break down Claude Code costs across projects, sessions, or days.
---

# Project Usage

Run the bundled aggregator. Pass through whatever window the user asked for.

```bash
~/.claude/skills/project-usage/scripts/aggregate.py [arg] [--sessions]
```

Arg values:
- *(omitted)* or `week` — rolling 7 days, project × day matrix (default)
- `today` — UTC today only
- `YYYY-MM-DD` — a specific UTC day
- `month` — rolling 30 days, project × day matrix
- `all` — every recorded day, project × month matrix

`--sessions` adds a per-session detail table at the bottom. Use it when the user asks "which session", "longest session", or wants to drill below project granularity.

## Output

Default is a project × bucket cost matrix with row/column/grand totals, then a model-mix summary. Print the script's stdout verbatim — do not re-format unless the user asks.

## Pricing

The script uses pricing calibrated against Claude Code's own `/usage` panel:

| model | in | out | cacheR | cacheW | per M tokens |
|---|---|---|---|---|---|
| opus-4-7 | $5 | $25 | $0.50 | $6.25 |
| sonnet-4-6 | $3 | $15 | $0.30 | $3.75 |
| haiku-4-5 | $1 | $5 | $0.10 | $1.25 |

If Anthropic publishes new rates, edit `PRICES` at the top of `scripts/aggregate.py`. If a session's `/usage` figure disagrees with the script, recalibrate against the panel — `/usage` is ground truth.

## Caveats to mention only if asked

- Times are UTC (matches the JSONL timestamps).
- Sub-agent transcripts (`subagents/*.jsonl`) are folded into their parent project's totals.
- Cache writes don't distinguish 5m vs 1h ephemeral; the single rate is an average.
- A session may show higher cost here than in its live `/usage` panel because the panel is a snapshot; the JSONL keeps growing.
