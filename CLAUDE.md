# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

N4C-NETTOOLS is a Z80 assembly language network library for the Amstrad CPC microcomputer with Net4CPC (W5100S Ethernet) hardware. It is a shared reference library — applications copy only the files they need into their own source trees; there is no shared compiled output. The primary consumer is n4cewenterm (an ANSI Telnet terminal client).

## Build

The assembler is RASM. Each example has its own build script. There is no top-level Makefile.

```bash
# Build the DNS test example
cd examples
./build_dnstest.sh        # Uses $RASM env var or 'rasm' from PATH; outputs bin/DNS.BIN
```

Output binaries (`.BIN`, `.bin`, `bin/`) are gitignored. There are no tests, no linter, and no CI.

## Source Components

All library source is in `src/`. Files are assembled directly into consumer applications.

| File | Role |
|------|------|
| `src/w5100.s` | W5100S Ethernet chip driver — socket open/close, TCP connect/send/recv, UDP sendto, register and buffer access. ~40 exported functions. |
| `src/dns_simple.s` | DNS resolver (RFC 1034 A-record lookups). Uses a UDP socket, encodes/decodes DNS packets, 3000 ms timeout. Entry point: `RESOLVE_HOSTNAME`. |
| `src/n4c-netinit-kv.s` | Reads `N4C.CFG` (key=value format) from disk, parses IP/mask/gateway/DNS addresses, and writes them into W5100S registers. Preferred initializer. |
| `src/n4c-netinit.s` | Simpler alternative initializer (no file parsing). |

## Hardware Constants

- W5100S I/O base: `0xFD20–0xFD23` (hardcoded in `w5100.s`)
- DNS timeout: 3000 ms (hardcoded in `dns_simple.s`)
- Primary socket: Socket 0

## AMSDOS Firmware Vector Map (USB/FAT drive)

The CPC is running from a USB drive formatted with FAT. Its AMSDOS inserts one extra entry before the standard CAS INPUT section, shifting **CAS IN routines +3** from standard CPC ROM addresses. CAS OUT routines remain at **standard** addresses.

| Routine | Standard | USB drive | Notes |
|---------|----------|-----------|-------|
| CAS_IN_OPEN | &BC74 | &BC77 | confirmed working |
| CAS_IN_CLOSE | &BC77 | &BC7A | |
| CAS_IN_CHAR | &BC7D | &BC80 | |
| CAS_IN_DIRECT | &BC80 | &BC83 | confirmed working |
| CAS_OUT_OPEN | &BC8C | &BC8C | no shift — standard address |
| CAS_OUT_CLOSE | &BC8F | &BC8F | no shift |
| CAS_OUT_ABANDON | &BC92 | &BC92 | calling this by mistake = write fails |
| CAS_OUT_CHAR | &BC95 | &BC95 | no shift |
| CAS_CATALOG | &BC9E | &BC9E | no shift |

All CAS routines: **carry SET = success, carry CLEAR = failure**.

## Network Configuration File

`N4C.CFG` (key=value, one entry per line):

```
IP=192.168.1.100
MASK=255.255.255.0
GW=192.168.1.1
DNS=8.8.8.8
```

See `N4C.CFG.example` and `docs/CONFIG.md` for details.

## CPC BASIC Variable Naming

The Locomotive BASIC tokenizer scans left-to-right and greedily matches keywords at the start of each token. Any variable name that begins with a complete BASIC keyword will be silently mis-tokenised, causing a runtime syntax error.

Common dangerous prefixes to avoid at the start of a variable name:

| Prefix | Keyword | Bad example | Safe alternative |
|--------|---------|-------------|-----------------|
| `FN` | user-defined function call | `fname$` | `dfn$` |
| `FOR` | loop | `format$` | `dfmt$` |
| `NOT` | logical NOT | `notes$` | `nts$` |
| `OR` | logical OR | `origin` | `orig` |
| `AND` | logical AND | `android` | `droid` |
| `INT` | integer function | `interval` | `ivl` |
| `TO` | range in FOR | `total` | `ttl` |
| `THEN` | IF branch | `theme$` | `thm$` |
| `MOD` | modulo | — | — |

This only applies to the **start** of a name. `amsfname$` is safe because `AMS` does not match any keyword, so the tokenizer commits to reading a variable name before reaching the `fn` in the middle.

## CPC File Format Requirements

Any text file that the CPC will read (e.g. `N4C.CFG`, BASIC loaders like `WGET.BAS`, or any data file consumed by running programs) **must use CR+LF (`\r\n`) line endings**, not Unix LF-only. The Amstrad CPC and AMSDOS expect `0x0D 0x0A` as the line terminator; files with Unix-only `\n` will be misread.

When creating or editing files destined for the CPC disk, ensure line endings are set correctly:

```bash
# Convert a file to CR+LF before copying to the CPC disk
unix2dos N4C.CFG
# or
sed -i 's/$/\r/' N4C.CFG
```

This applies to every file written from the host machine that the CPC will open — including config files, BASIC programs saved as ASCII, and any plain-text data files.

## Documentation

| File | Contents |
|------|----------|
| `README.md` | Complete function reference, usage examples, W5100S register map, bug patterns |
| `docs/BUGS_FIXED.md` | Catalogue of 9 critical bugs found during DNS development — essential reading before touching dns_simple.s |
| `docs/PROJECT_STRUCTURE.md` | Shared-library design rationale and application integration patterns |
| `docs/N4C-NETINIT.md` | n4c-netinit function reference and usage examples |
| `docs/CONFIG.md` | N4C.CFG format and user guide |
