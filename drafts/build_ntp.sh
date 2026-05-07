#!/bin/bash
# Build NTP time client for Net4CPC

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

echo "Building NTP for Net4CPC..."
echo "Using: $RASM"

mkdir -p bin

echo "Copying library files..."
cp ../src/w5100.s .
cp ../src/dns_simple.s .
cp ../src/n4c-netinit-kv.s .

echo "Assembling ntp.s..."
$RASM ntp.s

rm -f w5100.s dns_simple.s n4c-netinit-kv.s

if [ $? -eq 0 ]; then
    mv NTP.BIN bin/ 2>/dev/null

    echo ""
    echo "Build successful!"
    echo ""
    echo "Files generated in bin/:"
    echo "  - NTP.BIN ($(stat -c%s bin/NTP.BIN) bytes)"
    echo ""
    echo "Files to copy to your CPC disk:"
    echo "  1. NTP.BAS (BASIC loader)"
    echo "  2. bin/NTP.BIN (NTP client)"
    echo "  3. N4C.CFG (network configuration)"
    echo ""
    echo "On CPC:"
    echo "  RUN\"NTP"
    echo ""
    echo "Displays current UTC date and time from pool.ntp.org"
else
    echo "Build failed!"
    rm -f w5100.s dns_simple.s n4c-netinit-kv.s
    exit 1
fi
