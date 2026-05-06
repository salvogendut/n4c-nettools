#!/bin/bash
# Build WGET program for Net4CPC

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

echo "Building WGET for Net4CPC..."
echo "Using: $RASM"

# Create bin directory if it doesn't exist
mkdir -p bin

# Copy library files to current directory for assembly
echo "Copying library files..."
cp ../src/w5100.s .
cp ../src/dns_simple.s .
cp ../src/n4c-netinit-kv.s .

# Assemble
echo "Assembling wget.s..."
$RASM wget.s

# Clean up library copies
rm -f w5100.s dns_simple.s n4c-netinit-kv.s

if [ $? -eq 0 ]; then
    # Move binary to bin directory (RASM SAVE directive outputs to current dir)
    mv WGET.BIN bin/ 2>/dev/null

    echo ""
    echo "Build successful!"
    echo ""
    echo "Files generated in bin/:"
    echo "  - WGET.BIN ($(stat -c%s bin/WGET.BIN) bytes)"
    echo ""
    echo "Files to copy to your CPC disk:"
    echo "  1. WGET.BAS (BASIC loader with URL input)"
    echo "  2. bin/WGET.BIN (wget program)"
    echo "  3. N4C.CFG (network configuration - see N4C.CFG.example)"
    echo ""
    echo "On CPC:"
    echo "  RUN\"WGET"
    echo ""
    echo "You will be prompted to enter a URL like:"
    echo "  http://example.com/files/test.txt"
    echo ""
    echo "The program will parse the URL, resolve the hostname via DNS,"
    echo "and download the file to disk with an auto-generated AMSDOS filename."
else
    echo "Build failed!"
    # Clean up library copies on failure too
    rm -f w5100.s dns_simple.s n4c-netinit-kv.s
    exit 1
fi
