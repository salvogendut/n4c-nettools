#!/bin/bash
# Create N4C.CFG with proper CPC-compatible line endings (CR+LF)
# Output goes to the current directory (copy to your CPC disk)

OUTFILE="N4C.CFG"

if [ -f "$OUTFILE" ]; then
    echo "WARNING: $OUTFILE already exists!"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

echo "Creating $OUTFILE..."
echo ""
echo "Enter your network configuration:"
echo "(Press ENTER to use the default shown in brackets)"
echo ""

read -p "IP Address [192.168.1.100]: " IP
IP=${IP:-192.168.1.100}

read -p "Netmask [255.255.255.0]: " NETMASK
NETMASK=${NETMASK:-255.255.255.0}

read -p "Gateway [192.168.1.1]: " GATEWAY
GATEWAY=${GATEWAY:-192.168.1.1}

read -p "DNS Server [192.168.1.1]: " DNS
DNS=${DNS:-192.168.1.1}

# Write with Unix line endings first, then convert
printf "IP=%s\nMASK=%s\nGW=%s\nDNS=%s\n" "$IP" "$NETMASK" "$GATEWAY" "$DNS" > "$OUTFILE"

# Convert to CR+LF for CPC/AMSDOS
if command -v unix2dos &> /dev/null; then
    unix2dos "$OUTFILE" 2>/dev/null
else
    perl -pi -e 's/\r?\n/\r\n/' "$OUTFILE" 2>/dev/null || sed -i 's/$/\r/' "$OUTFILE"
fi

echo ""
echo "$OUTFILE created with CR+LF line endings."
echo ""
echo "Contents:"
echo "  IP=$IP"
echo "  MASK=$NETMASK"
echo "  GW=$GATEWAY"
echo "  DNS=$DNS"
echo ""
echo "Copy this file to your CPC disk along with the binaries."
