---
name: skill-creator
description: Create new Claude Code skills through natural dialogue. Triggers on requests to create, build, or make a new skill. Fetches latest Anthropic documentation before starting, interviews the user to understand requirements, and generates minimal, focused skills.
---

# Skill Creator

Create new skills through interview-driven dialogue.

## Before Creating Any Skill

Fetch current Anthropic guidance:

```bash
~/.claude/skills/skill-creator/scripts/fetch-docs.sh
```

Parse the output. If it conflicts with instructions here, Anthropic's docs win unless marked `#override`.

## Interview Process

**MUST use the AskUserQuestion tool** for all clarifying questions. Never ask questions in plain text — always use the tool. #override

Understand via AskUserQuestion:
- What problem does this skill solve?
- What would trigger it? (concrete prompts the user would say)
- What does Claude currently get wrong or not know?
- What outputs should it produce?
- What files/scripts/references would help?

Keep probing until you have concrete examples of use. Use 1-4 questions per AskUserQuestion call.

## Creating the Skill

Run the init script:

```bash
~/.claude/skills/skill-creator/scripts/init.py <skill-name>
```

Output location: `~/.claude/skills/<skill-name>/`

### Philosophy #override

Every line must justify its token cost. Challenge each piece:
- Does Claude really need this?
- Could this be shorter?
- Is this obvious to Claude already?

A skill is perfect not when there's nothing more to add, but when there's nothing left to remove.

### SKILL.md Format

```markdown
---
name: skill-name
description: What it does + when to trigger. Be specific — this is how Claude decides to use it.
---

# Skill Name

[Concise instructions. Imperative voice. No fluff.]
```

### Deviations

If the user requests something that differs from Anthropic's guidance, mark it:

```markdown
Do X instead of Y. #override
```

## After Creation

Inform the user:
- Skill saved to `~/.claude/skills/<name>/`
- They can test it immediately
- Use skill-review to update it with lessons learned
