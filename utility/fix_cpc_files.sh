#!/bin/bash
# Fix line endings for all CPC files (BASIC loaders and config files)
# Run from anywhere: ./utility/fix_cpc_files.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fix_crlf() {
    local file="$1"
    if file "$file" | grep -q "CRLF"; then
        echo "  $file: already CR+LF"
    else
        perl -pi -e 's/\r?\n/\r\n/' "$file"
        echo "  $file: converted to CR+LF"
    fi
}

echo "Fixing line endings for CPC compatibility..."
echo ""

# BASIC loaders in all output directories (albireo/, standard/, and legacy flat layout)
while IFS= read -r -d '' file; do
    fix_crlf "$file"
done < <(find "$REPO_DIR/tools/bin" -name "*.BAS" -print0 2>/dev/null)

# Config example files in repo root
for file in "$REPO_DIR/N4C.CFG.example" "$REPO_DIR/N4C.CFG"; do
    if [ -f "$file" ]; then
        fix_crlf "$file"
    fi
done

echo ""
echo "Done! All files are now CPC-compatible."
