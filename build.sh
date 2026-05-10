#!/bin/bash
# Build all Net4CPC tools for both hardware targets.
# Output: tools/bin/albireo/  (USB/FAT Unidos roms — Albireo/GoTek)
#         tools/bin/standard/ (stock AMSDOS — ULIfAC and standard CPC hardware)
#
# Standard build: binaries read config from fixed RAM addresses (&3F10-&3F1F).
# The _STD.BAS loaders use BASIC OPENIN to read N4C.CFG and POKE those addresses
# before calling the binary.  The Albireo build reads N4C.CFG from within the
# binary itself via CAS firmware vectors.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/src"
BIN_ALBIREO="$REPO_DIR/tools/bin/albireo"
BIN_STANDARD="$REPO_DIR/tools/bin/standard"

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

mkdir -p "$BIN_ALBIREO" "$BIN_STANDARD"

# Build one tool for one hardware target.
# Args: tool_dir main_s bin_name bas_src bas_out rasm_flags out_dir label
#   bas_src = source .BAS filename (in tool_dir)
#   bas_out = output .BAS filename (in out_dir) — allows _STD.BAS -> NTP.BAS rename
build_tool() {
    local tool_dir="$SRC_DIR/$1"
    local main_s="$2"
    local bin_name="$3"
    local bas_src="$4"
    local bas_out="$5"
    local rasm_flags="$6"
    local out_dir="$7"
    local label="$8"

    cp "$SRC_DIR/w5100.s" "$SRC_DIR/dns_simple.s" "$SRC_DIR/n4c-netinit-kv.s" "$tool_dir/"
    (cd "$tool_dir" && $RASM $rasm_flags "$main_s") 2>&1 | grep -E "error|FAILED|Write binary"
    local status=${PIPESTATUS[0]}
    rm -f "$tool_dir/w5100.s" "$tool_dir/dns_simple.s" "$tool_dir/n4c-netinit-kv.s"

    if [ $status -ne 0 ]; then
        echo "  FAILED: $bin_name [$label]"
        return 1
    fi

    mv "$tool_dir/$bin_name" "$out_dir/"
    cp "$tool_dir/$bas_src" "$out_dir/$bas_out"
    echo "  OK: $bin_name -> $(basename $out_dir)/"
}

# Build n4cewenterm (two separate assemblies: charset + main binary).
# Args: rasm_flags out_dir label bas_src
build_ewenterm() {
    local rasm_flags="$1"
    local out_dir="$2"
    local label="$3"
    local bas_src="$4"
    local ewen_dir="$SRC_DIR/n4cewenterm"

    cp "$SRC_DIR/w5100.s" "$SRC_DIR/dns_simple.s" "$SRC_DIR/n4c-netinit-kv.s" "$ewen_dir/"
    (cd "$ewen_dir" && $RASM charset.s && $RASM $rasm_flags termN4C.s) 2>&1 | grep -E "error|FAILED|Write binary"
    local status=${PIPESTATUS[0]}
    rm -f "$ewen_dir/w5100.s" "$ewen_dir/dns_simple.s" "$ewen_dir/n4c-netinit-kv.s"

    if [ $status -ne 0 ]; then
        echo "  FAILED: n4cewenterm [$label]"
        return 1
    fi

    mv "$ewen_dir/CHARSET.BIN" "$out_dir/"
    mv "$ewen_dir/N4CEWEN.BIN" "$out_dir/"
    cp "$ewen_dir/$bas_src" "$out_dir/N4CEWEN.BAS"
    echo "  OK: CHARSET.BIN + N4CEWEN.BIN -> $(basename $out_dir)/"
}

echo ""
echo "=== Albireo / Unidos (USB/FAT) ==="
build_tool ntp  ntp.s  NTP.BIN  NTP.BAS  NTP.BAS  "-DAMSDOS_USB=1" "$BIN_ALBIREO" "albireo" || exit 1
build_tool wget wget.s WGET.BIN WGET.BAS  WGET.BAS  "-DAMSDOS_USB=1" "$BIN_ALBIREO" "albireo" || exit 1
build_ewenterm "-DAMSDOS_USB=1" "$BIN_ALBIREO" "albireo" "N4CEWEN.BAS" || exit 1

echo ""
echo "=== Standard AMSDOS (ULIfAC / stock CPC) ==="
build_tool ntp  ntp.s  NTP.BIN  NTP_STD.BAS  NTP.BAS  "" "$BIN_STANDARD" "standard" || exit 1
build_tool wget wget.s WGET.BIN WGET_STD.BAS  WGET.BAS  "" "$BIN_STANDARD" "standard" || exit 1
build_ewenterm "" "$BIN_STANDARD" "standard" "N4CEWEN_STD.BAS" || exit 1

echo ""
echo "Fixing CR+LF line endings in .BAS files..."
while IFS= read -r -d '' file; do
    perl -pi -e 's/\r?\n/\r\n/' "$file"
done < <(find "$BIN_ALBIREO" "$BIN_STANDARD" -name "*.BAS" -print0)

echo ""
echo "Built files:"
echo "  tools/bin/albireo/:" && ls -lh "$BIN_ALBIREO/"
echo "  tools/bin/standard/:" && ls -lh "$BIN_STANDARD/"
