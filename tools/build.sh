#!/bin/bash
# Build all Net4CPC tools
# Outputs .BIN and .BAS files to tools/built/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"
BUILT_DIR="$SCRIPT_DIR/built"

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

mkdir -p "$BUILT_DIR"

LIBS="w5100.s dns_simple.s n4c-netinit-kv.s"

build_tool() {
    local dir="$SCRIPT_DIR/$1"
    local src="$2"
    local bin="$3"
    local bas="$4"

    echo ""
    echo "Building $bin..."

    cp $SRC_DIR/w5100.s $SRC_DIR/dns_simple.s $SRC_DIR/n4c-netinit-kv.s "$dir/"

    (cd "$dir" && $RASM "$src")
    local status=$?

    rm -f "$dir/w5100.s" "$dir/dns_simple.s" "$dir/n4c-netinit-kv.s"

    if [ $status -ne 0 ]; then
        echo "FAILED: $bin"
        return 1
    fi

    mv "$dir/$bin" "$BUILT_DIR/"
    cp "$dir/$bas" "$BUILT_DIR/"
    echo "OK: $bin -> built/"
}

build_tool ntp   ntp.s   NTP.BIN  NTP.BAS
build_tool wget  wget.s  WGET.BIN WGET.BAS

echo ""
echo "Built files:"
ls -lh "$BUILT_DIR/"
