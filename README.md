# N4C-NETTOOLS — Network Library and Tools for Net4CPC

Z80 assembly network library and ready-to-run tools for the Amstrad CPC with [Net4CPC](https://github.com/salafek/Net4CPC) (W5100S Ethernet) hardware.

## What's in the box

| Item | Description |
|------|-------------|
| `src/w5100.s` | W5100S chip driver — sockets, TCP, UDP, buffers |
| `src/dns_simple.s` | DNS resolver (RFC 1034 A-record lookups) |
| `src/n4c-netinit-kv.s` | Reads `N4C.CFG`, configures W5100S — preferred initializer |
| `src/n4c-netinit.s` | Simpler alternative initializer (no file parsing) |
| `src/ntp/` | SNTPv4 time client — resolves pool, displays UTC date/time |
| `src/wget/` | HTTP file downloader — fetches files from a URL and saves to disk |
| `src/n4cewenterm/` | ANSI Telnet terminal client — full VT100/ANSI emulation over TCP |

## Hardware targets

Two builds are produced, differing in how network config is read from `N4C.CFG`:

| Target | Hardware | `tools/bin/` folder | Config loading |
|--------|----------|---------------------|----------------|
| **Albireo** | Albireo / GoTek with USB/FAT Unidos roms | `tools/bin/albireo/` | Binary reads `N4C.CFG` directly via CAS firmware |
| **Standard** | ULIfAC, stock CPC AMSDOS | `tools/bin/standard/` | BASIC loader reads `N4C.CFG` via `OPENIN`, POKEs config to RAM before calling binary |

The standard build exists because on ULIfAC (and other setups where the disc ROM patches BASIC commands rather than the CAS firmware vectors), calling `CAS_IN_OPEN` from machine code hits the tape AMSDOS rather than the disc. BASIC's `OPENIN` is intercepted by the disc ROM and works correctly, so the `.BAS` loader handles the file reading instead.

## Quick start — running the tools

Copy the correct folder's files to your CPC disk along with `N4C.CFG`.

**Albireo / GoTek (USB/FAT Unidos):** use `tools/bin/albireo/`  
**ULIfAC / stock AMSDOS:** use `tools/bin/standard/`

**NTP** — display current UTC time:
```
NTP.BIN  NTP.BAS  N4C.CFG
```
```basic
RUN"NTP
```

**WGET** — download a file from a web server:
```
WGET.BIN  WGET.BAS  N4C.CFG
```
```basic
RUN"WGET
```
The BASIC loader prompts for a URL and saves the file to disk.

**n4cewenterm** — ANSI Telnet terminal:
```
N4CEWEN.BIN  N4CEWEN.BAS  CHARSET.BIN  N4C.CFG
```
```basic
RUN"N4CEWEN
```

## Building from source

Requires [RASM](https://github.com/EdouardBERGE/rasm) assembler.

```bash
./build.sh
```

Both hardware targets are built in one run:

```
tools/bin/albireo/   NTP.BIN  NTP.BAS  WGET.BIN  WGET.BAS  N4CEWEN.BIN  N4CEWEN.BAS  CHARSET.BIN
tools/bin/standard/  NTP.BIN  NTP.BAS  WGET.BIN  WGET.BAS  N4CEWEN.BIN  N4CEWEN.BAS  CHARSET.BIN
```

CR+LF line endings are applied to all `.BAS` output files automatically.

To use a specific RASM binary:
```bash
RASM=/path/to/rasm ./build.sh
```

## Project layout

```
src/
  w5100.s               W5100S driver (library)
  dns_simple.s          DNS resolver (library)
  n4c-netinit-kv.s      N4C.CFG reader + W5100S init (library)
  n4c-netinit.s         Simple initializer (library)
  ntp/
    ntp.s               SNTPv4 time client
    NTP.BAS             Albireo BASIC loader (binary reads N4C.CFG)
    NTP_STD.BAS         Standard BASIC loader (BASIC reads N4C.CFG)
  wget/
    wget.s              HTTP file downloader
    WGET.BAS            Albireo BASIC loader
    WGET_STD.BAS        Standard BASIC loader
  n4cewenterm/
    termN4C.s           Main entry point
    charset.s           Code page 437 character set (loaded at 0x6800)
    main.s  ansiterm.s  screen.s  telnetfunc_n4c.s
    negotiate.s  urlmenu_n4c.s  data.s
    N4CEWEN.BAS         Albireo BASIC loader
    N4CEWEN_STD.BAS     Standard BASIC loader
tools/
  bin/
    albireo/            Albireo/GoTek build — copy this to USB/FAT disk
      NTP.BIN  NTP.BAS  WGET.BIN  WGET.BAS
      N4CEWEN.BIN  N4CEWEN.BAS  CHARSET.BIN
    standard/           Standard AMSDOS build — copy this to ULIfAC disk
      NTP.BIN  NTP.BAS  WGET.BIN  WGET.BAS
      N4CEWEN.BIN  N4CEWEN.BAS  CHARSET.BIN
build.sh                Builds all tools for both targets → tools/bin/
utility/
  create_config.sh      Interactive N4C.CFG generator (CR+LF output)
  fix_cpc_files.sh      Convert BAS/CFG files to CR+LF for CPC disk
examples/
  dnstest.s             Library usage example (DNS resolution)
docs/
  BUGS_FIXED.md         Catalogue of bugs found and fixed
  CONFIG.md             N4C.CFG format reference
  N4C-NETINIT.md        Initializer function reference
  PROJECT_STRUCTURE.md  Library design rationale
N4C.CFG.example         Example network configuration
```

## Configuration

Create `N4C.CFG` on your CPC disk (CR+LF line endings required):

```
IP=192.168.1.100
MASK=255.255.255.0
GW=192.168.1.1
DNS=8.8.8.8
```

Use the interactive helper to generate it with correct line endings:

```bash
./utility/create_config.sh
```

See `docs/CONFIG.md` for full details.

## Utility scripts

| Script | Purpose |
|--------|---------|
| `utility/create_config.sh` | Interactive prompt to create `N4C.CFG` with correct CR+LF line endings |
| `utility/fix_cpc_files.sh` | Convert all `.BAS` and `.CFG` files in `tools/bin/` to CR+LF for CPC compatibility |

The CPC and AMSDOS require `CR+LF` (`\r\n`) line endings in all text files. `build.sh` applies this automatically to output `.BAS` files. Run `fix_cpc_files.sh` if you edit a loader or config file manually.

## Library reference

### `w5100.s` — W5100S driver

Provides socket-based networking on top of the W5100S chip.

**Socket lifecycle:**
- `SOCKET` — open socket (A=0xFF auto, D=SK_STREAM/SK_DGRAM, E=flags) → A=socket#
- `CONNECT` — TCP connect (HL=IP, BC=port)
- `CLOSE` — close socket (A=socket#)

**TCP data transfer:**
- `NET_SEND` — send buffer (HL=buf, BC=len)
- `NET_RECV` — receive 1 byte (HL=buf) → BC=1 if data, 0 if empty
- `CHECK_CONNECTION` — carry clear if connected, set if disconnected

**UDP data transfer:**
- `SENDTO` — send datagram (A=socket, HL=buf, BC=len, DE=peer: 4-byte IP + 2-byte port)
- `SELECT` — check RX data (A=socket, E=SL_RECV) → carry clear if data available

**Low-level access:**
- `W5100_READ_REG` / `W5100_WRITE_REG` — single register (HL=addr)
- `W5100_READ_BUF` / `W5100_WRITE_BUF` — block transfer (HL=host buf, DE=W5100S addr, BC=len)

**Utilities:**
- `N_DPRT` — get dynamic source port → HL (cycles 0xC001–0xC0FF)
- `N_TIME` — read CPC frame counter → HL (1/50 s units)

**Socket modes:** `SK_STREAM` (1=TCP), `SK_DGRAM` (2=UDP)  
**Hardware I/O:** 0xFD20–0xFD23  
**Socket registers:** Socket 0 base 0x0400, Socket 1 base 0x0500 (stride 0x0100)  
**TX/RX buffers:** 2 KB each; Socket 0 TX 0x4000, RX 0x6000; Socket 1 TX 0x4800, RX 0x6800

### `dns_simple.s` — DNS resolver

```z80
    ld  hl, hostname    ; null-terminated string
    ld  de, ip_buffer   ; 4-byte result
    call RESOLVE_HOSTNAME
    jr  c, dns_error    ; A = error code on failure
```

Error codes: 16 socket, 18 build, 19 send, 20 timeout, 21–27 parse errors.  
Timeout: 3000 ms. Uses Socket 1 (UDP).

### `n4c-netinit-kv.s` — network initializer

```z80
    call N4C_INIT
    jr  c, init_error   ; carry set = config missing or W5100S not responding
    ; W5100S is now configured and ready
```

**Albireo build** (`-DAMSDOS_USB=1`): `N4C_INIT` opens `N4C.CFG` via `CAS_IN_DIRECT`, parses the key=value pairs (IP, MASK, GW, DNS), and writes them into the W5100S registers.

**Standard build**: `N4C_INIT` skips file I/O entirely and reads config from fixed RAM addresses `&3F10–&3F1F`, which the BASIC loader has already filled by the time the binary is called. The BASIC loader uses `OPENIN` / `INPUT #9` / `CLOSEIN` to read `N4C.CFG`.

Standard RAM layout (POKEd by BASIC before `CALL`):

| Address | Content |
|---------|---------|
| `&3F10–&3F13` | IP address |
| `&3F14–&3F17` | Netmask |
| `&3F18–&3F1B` | Gateway |
| `&3F1C–&3F1F` | DNS server |

## AMSDOS firmware vectors

Two hardware variants are supported. The build flag `-DAMSDOS_USB=1` selects the Albireo/GoTek vector set; the standard build uses stock CPC addresses.

| Routine | Standard CPC (`&`) | USB/FAT Unidos (`&`) |
|---------|--------------------|----------------------|
| CAS_IN_OPEN | BC74 | BC77 |
| CAS_IN_CLOSE | BC77 | BC7A |
| CAS_IN_CHAR | BC7D | BC80 |
| CAS_IN_DIRECT | BC80 | BC83 |
| CAS_OUT_OPEN | BC8C | BC8C |
| CAS_OUT_CLOSE | BC8F | BC8F |
| CAS_OUT_CHAR | BC95 | BC95 |

All CAS routines: carry SET = success, carry CLEAR = failure.

The USB/FAT Unidos firmware inserts one extra entry before the standard CAS INPUT section, shifting all CAS IN vectors +3. CAS OUT addresses are identical on both.

On ULIfAC and similar setups, `CAS_IN_OPEN` at &BC74 points to tape AMSDOS, not disc. BASIC's `OPENIN` statement is intercepted at a higher level by the disc ROM and works correctly — hence the two-loader approach.

## Using the library in your own project

Copy the files you need to your project's source directory:

```bash
cp n4c-nettools/src/w5100.s           your-project/
cp n4c-nettools/src/dns_simple.s      your-project/   # if you need DNS
cp n4c-nettools/src/n4c-netinit-kv.s  your-project/   # recommended init
```

Then include them at the bottom of your main assembly file:

```z80
    include "n4c-netinit-kv.s"
    include "w5100.s"
    include "dns_simple.s"
```

Build with `-DAMSDOS_USB=1` for Albireo/GoTek; omit the flag for ULIfAC/standard AMSDOS. Each application keeps its own copy — no shared build output, no external dependency at assemble time.

## Notable bugs found and fixed

### `w5100.s` — SENDTO TX write pointer corruption
`ld h, a` saved the TX_WR MSB, then `ld hl, S1_TX_WR0+1` immediately overwrote H with 0x05 (the high byte of the register address). On a fresh socket where TX_WR = 0x0000, this caused SENDTO to tell the W5100S to transmit 1328 bytes instead of the true payload length. DNS servers silently ignore trailing garbage; NTP servers discard packets that aren't exactly 48 bytes. Fixed by saving MSB in D, LSB in E, then `ex de, hl` before `add hl, bc`.

### `dns_simple.s` — answer NAME only handled compressed pointers
`dns_parse_response` returned error 23 for any DNS answer whose NAME field was not a compression pointer (0xC0 xx). Home router DNS caches return uncompressed label sequences on repeat queries, causing reliable DNS failure on the second and subsequent runs. Fixed by adding a label-skip loop (mirrors the QNAME skip in the question section) with fallthrough to pointer handling.

### `w5100.s` — N_DPRT always returned the same source port
N_DPRT was supposed to read the W5100S source port register to generate a dynamic port, but the address calculation corrupted the register address, always reading 0xC037 (undefined). Fixed by replacing the register-read approach with an in-RAM counter (`dprt_seq`) cycling 0x01–0xFF, giving ports 0xC001–0xC0FF.

### `w5100.s` — CHECK_CONNECTION always returned caller's carry
`push af / scf / or a / pop af` sequence restored the caller's carry flag through the final `pop af`, making CHECK_CONNECTION always report the previous carry state. Fixed by removing the push/pop wrapper.

Full bug catalogue: `docs/BUGS_FIXED.md`

## Examples

`examples/dnstest.s` — standalone DNS resolution test. Resolves `google.com` and prints the IP.

```bash
cd examples && ./build_dnstest.sh
```

## Applications using this library

- **n4cewenterm** — ANSI Telnet terminal client (now part of this repo, `src/n4cewenterm/`)

## Credits

- Based on KCNet DNS client by susowa (2008) and salafek (2023)
- Adapted for Net4CPC W5100S hardware (2026)
- Bugs found and fixed through hardware testing on a real CPC 464 with 1Mb of RAM, a Net4CPC device and a CPC PicoRom (with USB module)

## License

Open source — use freely in your own Amstrad CPC network projects.
