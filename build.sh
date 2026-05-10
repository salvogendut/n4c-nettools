#!/bin/bash
# Build all Net4CPC tools.
# Output: tools/bin/
#
# Config is read from fixed RAM addresses (&3F10-&3F1F); the .BAS loader uses
# BASIC OPENIN to read N4C.CFG and POKEs those addresses before calling the binary.
# This approach works on all hardware (Albireo, ULIfAC, stock AMSDOS).

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/src"
BIN_DIR="$REPO_DIR/tools/bin"

if [ -n "$RASM" ]; then
    echo "Using RASM from environment: $RASM"
elif command -v rasm &> /dev/null; then
    RASM=rasm
else
    echo "ERROR: RASM assembler not found!"
    echo "Please either:"
    echo "  1. Install RASM and add to PATH, or"
    echo "  2. Set RASM environment variable to rasm executable path"
    echo ""
    echo "Example: export RASM=/path/to/rasm.exe"
    exit 1
fi

mkdir -p "$BIN_DIR"

build_tool() {
    local tool_dir="$SRC_DIR/$1"
    local main_s="$2"
    local bin_name="$3"
    local bas_name="$4"

    cp "$SRC_DIR/w5100.s" "$SRC_DIR/dns_simple.s" "$SRC_DIR/n4c-netinit-kv.s" "$tool_dir/"
    (cd "$tool_dir" && $RASM "$main_s") 2>&1 | grep -E "error|FAILED|Write binary"
    local status=${PIPESTATUS[0]}
    rm -f "$tool_dir/w5100.s" "$tool_dir/dns_simple.s" "$tool_dir/n4c-netinit-kv.s"

    if [ $status -ne 0 ]; then
        echo "  FAILED: $bin_name"
        return 1
    fi

    mv "$tool_dir/$bin_name" "$BIN_DIR/"
    cp "$tool_dir/$bas_name" "$BIN_DIR/"
    echo "  OK: $bin_name -> tools/bin/"
}

build_ewenterm() {
    local ewen_dir="$SRC_DIR/n4cewenterm"

    cp "$SRC_DIR/w5100.s" "$SRC_DIR/dns_simple.s" "$SRC_DIR/n4c-netinit-kv.s" "$ewen_dir/"
    (cd "$ewen_dir" && $RASM charset.s && $RASM termN4C.s) 2>&1 | grep -E "error|FAILED|Write binary"
    local status=${PIPESTATUS[0]}
    rm -f "$ewen_dir/w5100.s" "$ewen_dir/dns_simple.s" "$ewen_dir/n4c-netinit-kv.s"

    if [ $status -ne 0 ]; then
        echo "  FAILED: n4cewenterm"
        return 1
    fi

    mv "$ewen_dir/CHARSET.BIN" "$BIN_DIR/"
    mv "$ewen_dir/N4CEWEN.BIN" "$BIN_DIR/"
    cp "$ewen_dir/N4CEWEN.BAS" "$BIN_DIR/"
    echo "  OK: CHARSET.BIN + N4CEWEN.BIN -> tools/bin/"
}

echo ""
build_tool ntp  ntp.s  NTP.BIN  NTP.BAS  || exit 1
build_tool wget wget.s WGET.BIN WGET.BAS  || exit 1
build_ewenterm || exit 1

echo ""
echo "Fixing CR+LF line endings in .BAS files..."
while IFS= read -r -d '' file; do
    perl -pi -e 's/\r?\n/\r\n/' "$file"
done < <(find "$BIN_DIR" -maxdepth 1 -name "*.BAS" -print0)

echo ""
echo "Built files in tools/bin/:"
ls -lh "$BIN_DIR/"
