# N4C-NETTOOLS Project Structure

## Overview

The n4c-nettools project provides a shared networking library for developing network applications on the Amstrad CPC with Net4CPC (W5100S) hardware.

## Directory Structure

```
Dev/LEISURE/
├── n4c-nettools/              # Shared networking library
│   ├── README.md              # Library documentation
│   ├── src/                   # Core library source files
│   │   ├── w5100.s            # W5100S hardware driver
│   │   └── dns_simple.s       # DNS resolver
│   ├── docs/                  # Documentation
│   │   ├── BUGS_FIXED.md      # Catalog of bugs fixed during development
│   │   └── PROJECT_STRUCTURE.md  # This file
│   └── examples/              # Example programs
│       ├── dnstest.s          # DNS test program
│       ├── DNS.BAS            # BASIC loader for DNS test
│       └── build_dnstest.sh   # Build script for DNS test
│
├── n4cewenterm/               # Telnet terminal application
│   ├── README.md              # Application documentation
│   ├── build.sh               # Build script
│   ├── copy.sh                # Copy to disk image script
│   └── src/                   # Telnet-specific source files
│       ├── termN4C.s          # Main file (includes library files)
│       ├── main.s             # Entry point
│       ├── telnetfunc_n4c.s   # Telnet protocol
│       ├── urlmenu_n4c.s      # IP/hostname input, DNS integration
│       ├── negotiate.s        # Telnet IAC negotiation
│       ├── ansiterm.s         # ANSI escape sequence parser
│       ├── screen.s           # Screen manipulation
│       ├── charset.s          # Custom character set
│       ├── data.s             # Data tables
│       └── EWEN.BAS           # Network setup and loader
│
└── (future network applications...)
    ├── n4cftp/                # FTP client (planned)
    └── n4cping/               # Ping utility (planned)
```

## Shared Library (n4c-nettools)

### Purpose
Provides common networking functionality that can be used by multiple applications.

### Components
- **w5100.s** - Low-level W5100S chip driver
  - Socket management (TCP, UDP)
  - Data transmission/reception
  - Register and buffer access
  
- **dns_simple.s** - DNS client
  - Hostname to IP resolution
  - Implements RFC 1034
  - Error handling

### Usage
Applications include library files using relative paths:
```z80
    include "../../n4c-nettools/src/w5100.s"
    include "../../n4c-nettools/src/dns_simple.s"
```

## Applications

### n4cewenterm (Telnet Client)
**Status:** Complete and working

**Description:** ANSI terminal emulator with telnet protocol support. Can connect using hostnames or IP addresses.

**Dependencies:** w5100.s, dns_simple.s

**Key Features:**
- ANSI color and cursor control
- Telnet IAC negotiation
- DNS hostname resolution
- Custom port support

### Future Applications

**n4cftp (FTP Client)** - Planned
- File upload/download
- Directory listing
- Uses w5100.s for TCP connections

**n4cping (Ping Utility)** - Planned
- ICMP echo request/reply
- Network diagnostic tool
- Uses w5100.s for raw socket access

## Build Process

### Library Files
Library files (w5100.s, dns_simple.s) are not built separately. They are included by applications at build time.

### Applications
Each application has its own build script:
```bash
cd n4cewenterm
./build.sh          # Builds telnet client

cd ../n4c-nettools/examples
./build_dnstest.sh  # Builds DNS test example
```

### Adding New Applications

1. Create new directory alongside n4cewenterm
2. Include library files from n4c-nettools/src
3. Create application-specific source files
4. Create build script
5. Update this documentation

Example:
```
n4cftp/
├── README.md
├── build.sh
└── src/
    ├── ftpmain.s          # Includes ../n4c-nettools/src/w5100.s
    ├── ftpprotocol.s
    └── ftpcommands.s
```

## Version History

- **2026-05-05** - Library split from n4cewenterm
  - Created n4c-nettools shared library
  - Documented 9 bugs fixed during DNS development
  - DNS resolver fully integrated into telnet client
  
- **2026-05-04** - DNS resolver completed
  - Standalone DNS test working
  - Fixed 8 critical bugs
  
- **2026** - N4CEWENTERM development
  - Port from M4EWENTERM
  - Adapted for Net4CPC hardware

## Documentation

- `README.md` - Library overview and usage guide
- `docs/BUGS_FIXED.md` - Detailed bug catalog with fixes
- `docs/PROJECT_STRUCTURE.md` - This file
- `examples/` - Working example programs

## Contributing

When adding features or fixing bugs:
1. Update relevant source files
2. Test on actual hardware or emulator
3. Update documentation
4. Add examples if introducing new functionality

## License

Open source - use freely in your Amstrad CPC projects.
