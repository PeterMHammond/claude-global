---
name: pptx2png
description: Convert PowerPoint (.pptx) files to PNG images. Triggers on "convert pptx", "slides to images", "pptx to png", or when working with .pptx files that need image conversion.
---

# pptx2png

Convert .pptx slides to individual PNG images using LibreOffice and Poppler.

## Prerequisites

- `libreoffice-fresh` (provides `soffice`)
- `poppler` (provides `pdftoppm`)

## Usage

Run the conversion script:

```bash
~/.claude/skills/pptx2png/scripts/convert.sh <file.pptx> [output-dir]
```

- `file.pptx` — the PowerPoint file to convert (required)
- `output-dir` — where to write PNGs (optional, defaults to subdirectory named after the file)

## Output

- Individual slide PNGs at 200 DPI: `slide-01.png`, `slide-02.png`, etc.
- Zero-padded numbering (2 digits for <100 slides, 3 digits for 100+)

## Workflow

1. Locate the .pptx file(s) in the current project directory
2. Run the convert script for each .pptx file
3. Report the output directory and slide count to the user
