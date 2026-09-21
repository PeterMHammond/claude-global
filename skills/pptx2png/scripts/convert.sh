#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: convert.sh <file.pptx> [output-dir]"
    exit 1
fi

INPUT="$(realpath "$1")"

if [[ ! -f "$INPUT" ]]; then
    echo "File not found: $1"
    exit 1
fi

if [[ "${INPUT##*.}" != "pptx" ]]; then
    echo "Expected a .pptx file, got: $INPUT"
    exit 1
fi

STEM="$(basename "$INPUT" .pptx)"

if [[ $# -eq 2 ]]; then
    OUTPUT_DIR="$2"
else
    OUTPUT_DIR="$(dirname "$INPUT")/$STEM"
fi

mkdir -p "$OUTPUT_DIR"

# Step 1: PPTX → PDF via LibreOffice
echo "Converting PPTX to PDF..."
soffice --headless --convert-to pdf --outdir "$OUTPUT_DIR" "$INPUT"

PDF_PATH="$OUTPUT_DIR/$STEM.pdf"
if [[ ! -f "$PDF_PATH" ]]; then
    echo "Expected PDF not found: $PDF_PATH"
    exit 1
fi

# Step 2: PDF → PNG via pdftoppm (200 DPI)
echo "Converting PDF to PNG slides..."
pdftoppm -png -r 200 "$PDF_PATH" "$OUTPUT_DIR/slide"

# Step 3: Zero-pad slide numbers
cd "$OUTPUT_DIR"
SLIDES=(slide-*.png)
COUNT=${#SLIDES[@]}

if [[ $COUNT -ge 100 ]]; then
    WIDTH=3
else
    WIDTH=2
fi

INDEX=1
for OLD in "${SLIDES[@]}"; do
    NEW=$(printf "slide-%0${WIDTH}d.png" "$INDEX")
    if [[ "$OLD" != "$NEW" ]]; then
        mv "$OLD" "$NEW"
    fi
    echo "  $NEW"
    ((INDEX++))
done

# Clean up intermediate PDF
rm -f "$PDF_PATH"

echo "Done — $COUNT slides written to $OUTPUT_DIR"
