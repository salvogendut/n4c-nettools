#!/bin/bash
# Build all Net4CPC tools
# Sources: src/<tool>/  Libraries: src/
# Output:  tools/bin/

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

    echo ""
    echo "Building $bin_name..."

    cp "$SRC_DIR/w5100.s" "$SRC_DIR/dns_simple.s" "$SRC_DIR/n4c-netinit-kv.s" "$tool_dir/"

    (cd "$tool_dir" && $RASM "$main_s")
    local status=$?

    rm -f "$tool_dir/w5100.s" "$tool_dir/dns_simple.s" "$tool_dir/n4c-netinit-kv.s"

    if [ $status -ne 0 ]; then
        echo "FAILED: $bin_name"
        return 1
    fi

    mv "$tool_dir/$bin_name" "$BIN_DIR/"
    cp "$tool_dir/$bas_name" "$BIN_DIR/"
    echo "OK: $bin_name -> tools/bin/"
}

build_tool ntp  ntp.s  NTP.BIN  NTP.BAS
build_tool wget wget.s WGET.BIN WGET.BAS

echo ""
echo "Built files in tools/bin/:"
ls -lh "$BIN_DIR/"
