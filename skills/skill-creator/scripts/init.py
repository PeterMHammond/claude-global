#!/usr/bin/env python3
"""
Initialize a new skill directory.

Usage: init.py <skill-name>
Creates: ~/.claude/skills/<skill-name>/
"""

import sys
from pathlib import Path

SKILL_TEMPLATE = """---
name: {name}
description: [TODO: What it does + when to trigger]
---

# {title}

[TODO: Concise instructions. Imperative voice.]
"""

def main():
    if len(sys.argv) != 2:
        print("Usage: init.py <skill-name>")
        sys.exit(1)
    
    name = sys.argv[1]
    title = ' '.join(w.capitalize() for w in name.split('-'))
    skills_dir = Path.home() / '.claude' / 'skills'
    skill_dir = skills_dir / name
    
    if skill_dir.exists():
        print(f"Error: {skill_dir} already exists")
        sys.exit(1)
    
    skill_dir.mkdir(parents=True)
    (skill_dir / 'SKILL.md').write_text(SKILL_TEMPLATE.format(name=name, title=title))
    (skill_dir / 'scripts').mkdir()
    (skill_dir / 'references').mkdir()
    
    print(f"Created {skill_dir}/")
    print("  SKILL.md - edit this")
    print("  scripts/ - add executable code")
    print("  references/ - add detailed docs")

if __name__ == "__main__":
    main()
