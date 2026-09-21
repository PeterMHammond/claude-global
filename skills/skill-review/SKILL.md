---
name: skill-review
description: Update existing skills with lessons learned from actual use. Triggers on phrases like "update the skill", "it should have caught", "don't do that again", "add this to the skill", "lesson learned", or any feedback about skill performance.
---

# Skill Review

Update skills with lessons learned.

## When to Trigger

User says something like:
- "Update check-project so it catches X"
- "It should have found that .clone()"
- "Don't do that again"
- "Add this pattern to the skill"
- "Lesson learned: always check Y"

## Process

1. **Identify the skill** — Ask if unclear. List available:
   ```bash
   ~/.claude/skills/skill-review/scripts/list-skills.sh
   ```

2. **Read current skill** — `~/.claude/skills/<skill-name>/SKILL.md`

3. **Understand the lesson** — What went wrong? What should happen next time?

4. **Determine placement**:
   - Anti-pattern → add to anti-patterns section
   - New check → add to workflow/checklist
   - Detailed pattern → add to `references/lessons.md`

5. **Make minimal edit** — Add only what's needed

6. **Confirm** — Show what changed

## Adding Lessons

For quick patterns, add directly to SKILL.md:

```markdown
## Anti-patterns
- Don't use `.clone()` when borrowing suffices
```

For detailed lessons needing context, use references:

```bash
~/.claude/skills/skill-review/scripts/add-lesson.py <skill-name> "lesson text"
```

This appends to `<skill>/references/lessons.md` with timestamp.

## Edit Style

Keep lessons concise. The skill should grow in value, not size.

Bad: "Remember that one time we found a .clone() that wasn't needed because the value was only being read..."

Good: "Flag `.clone()` when value is only read"
