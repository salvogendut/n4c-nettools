#!/bin/bash
# Fix line endings for all CPC files (BASIC loaders and config files)
# Run from anywhere: ./utility/fix_cpc_files.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Fixing line endings for CPC compatibility..."
echo ""

# Fix BASIC loaders in tools/bin/
for file in "$REPO_DIR"/tools/bin/*.BAS; do
    if [ -f "$file" ]; then
        echo "Processing: $file"
        if file "$file" | grep -q "CRLF"; then
            echo "  Already has CR+LF line endings"
        else
            echo "  Converting to CR+LF..."
            perl -pi -e 's/\r?\n/\r\n/' "$file"
            echo "  Converted"
        fi
    fi
done

# Fix config example in repo root
for file in "$REPO_DIR"/N4C.CFG.example "$REPO_DIR"/N4C.CFG; do
    if [ -f "$file" ]; then
        echo "Processing: $file"
        if file "$file" | grep -q "CRLF"; then
            echo "  Already has CR+LF line endings"
        else
            echo "  Converting to CR+LF..."
            perl -pi -e 's/\r?\n/\r\n/' "$file"
            echo "  Converted"
        fi
    fi
done

echo ""
echo "Done! All files are now CPC-compatible."
echo ""
echo "Files ready to copy to CPC disk:"
ls -lh "$REPO_DIR"/tools/bin/*.BAS "$REPO_DIR"/tools/bin/*.BIN 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
