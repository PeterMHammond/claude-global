Retired 2026-09-21. codemunch was our own symbol index (the whole program is inline in SKILL.md).
It was replaced by Claude Code's LSP tool over rust-analyzer, which reads live files and answers
references and call hierarchy, and by Grep plus ranged Read for everything else. The index went
stale between reindexes (craft's was four days and 22 files behind) and could not run in a lab.
