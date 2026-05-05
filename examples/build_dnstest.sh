#!/bin/bash
# Build DNS test program for Net4CPC

# Try to find RASM
if [ -n "$RASM" ]; then
    # RASM environment variable is set
    echo "Using RASM from environment: $RASM"
elif command -v rasm &> /dev/null; then
    # rasm is in PATH
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

echo "Building DNS Test (n4c-nettools example)..."
echo "Using: $RASM"

# Create bin directory if it doesn't exist
mkdir -p bin

# Assemble
$RASM dnstest.s

if [ $? -eq 0 ]; then
    # Move binary to bin directory (RASM SAVE directive outputs to current dir)
    mv DNS.BIN bin/ 2>/dev/null

    echo ""
    echo "Build successful!"
    echo ""
    echo "Files generated in bin/:"
    echo "  - DNS.BIN ($(stat -c%s bin/DNS.BIN) bytes)"
    echo ""
    echo "Files to copy to your CPC:"
    echo "  1. DNS.BAS (BASIC loader)"
    echo "  2. bin/DNS.BIN (test program)"
    echo ""
    echo "Then on CPC: RUN\"DNS"
else
    echo "Build failed!"
    exit 1
fi
