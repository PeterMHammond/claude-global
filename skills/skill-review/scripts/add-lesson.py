#!/usr/bin/env python3
"""
Add a lesson to a skill's references/lessons.md

Usage: add-lesson.py <skill-name> "lesson text"
"""

import sys
from pathlib import Path
from datetime import datetime

def main():
    if len(sys.argv) != 3:
        print("Usage: add-lesson.py <skill-name> \"lesson text\"")
        sys.exit(1)
    
    skill_name = sys.argv[1]
    lesson = sys.argv[2]
    
    skills_dir = Path.home() / '.claude' / 'skills'
    skill_dir = skills_dir / skill_name
    
    if not skill_dir.exists():
        print(f"Error: Skill '{skill_name}' not found at {skill_dir}")
        sys.exit(1)
    
    refs_dir = skill_dir / 'references'
    refs_dir.mkdir(exist_ok=True)
    
    lessons_file = refs_dir / 'lessons.md'
    
    timestamp = datetime.now().strftime("%Y-%m-%d")
    entry = f"\n## {timestamp}\n\n{lesson}\n"
    
    if lessons_file.exists():
        content = lessons_file.read_text()
        lessons_file.write_text(content + entry)
    else:
        header = "# Lessons Learned\n\nPatterns and insights from actual use.\n"
        lessons_file.write_text(header + entry)
    
    print(f"Added lesson to {lessons_file}")

if __name__ == "__main__":
    main()
