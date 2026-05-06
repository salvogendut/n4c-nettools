# N4C-NETINIT - Shared Network Initialization Module

## Overview

The `n4c-netinit.s` module provides a standardized way to initialize Net4CPC (W5100S) hardware from a configuration file. This module should be included in all n4c-nettools applications for consistent network setup.

## Features

- ✅ Reads network configuration from `N4C.CFG` file
- ✅ Initializes W5100S hardware with config values
- ✅ Displays configuration to user
- ✅ Clear error messages for missing or invalid config
- ✅ Self-contained (no external dependencies)

## Usage in Your Application

### 1. Include the Module

In your main assembly file (before other includes):

```z80
    include "n4c-netinit.s"
    include "w5100.s"
    include "dns_simple.s"
    ; ... other includes
```

### 2. Call Initialization

At the start of your application (after screen setup):

```z80
start_app:
    ; Set up screen
    ld a, 2
    call SCR_SET_MODE

    ; Initialize network from config file
    call N4C_INIT
    jp c, init_error        ; Exit on error

    ; Network is ready - continue with your application
    ; ...

init_error:
    ; N4C_INIT failed, A contains error code
    ; Error message already displayed to user
    ret                     ; Exit to BASIC
```

### 3. Create Configuration File

Your application requires `N4C.CFG` on the same disk. Example:

```
192.168.1.100
255.255.255.0
192.168.1.1
192.168.1.1
```

## Function Reference

### N4C_INIT

Initialize Net4CPC hardware from configuration file.

**Entry:**
- None

**Exit:**
- Carry clear if successful
- Carry set on error
- A = error code if carry set

**Error Codes:**
- `N4C_ERR_NO_FILE` (1) - N4C.CFG not found
- `N4C_ERR_READ` (2) - Error reading configuration file
- `N4C_ERR_PARSE` (3) - Invalid configuration format
- `N4C_ERR_W5100` (4) - W5100S hardware not responding

**What It Does:**
1. Opens `N4C.CFG` file
2. Reads 4 lines (IP, Netmask, Gateway, DNS)
3. Parses IP addresses from ASCII to binary
4. Displays configuration on screen
5. Initializes W5100S registers
6. Verifies hardware responds correctly

**Screen Output (Success):**
```
N4C Network Initialization
IP Address: 192.168.1.100
Netmask:    255.255.255.0
Gateway:    192.168.1.1
DNS Server: 192.168.1.1
Network Ready
```

**Screen Output (Error):**
```
N4C Network Initialization
ERROR: N4C.CFG not found
```

## Configuration File Format

**Filename:** `N4C.CFG`  
**Format:** Plain text, 4 lines, one IP address per line

```
<IP Address>
<Netmask>
<Gateway>
<DNS Server>
```

Each line:
- Contains an IPv4 address in dotted decimal format
- Terminated by CR (13) or LF (10) or both
- Maximum 20 characters per line

Example:
```
192.168.1.100
255.255.255.0
192.168.1.1
8.8.8.8
```

## Internal Functions

The module provides several internal helper functions. You don't need to call these directly, but they're documented here for reference:

### n4c_read_ip_line
Reads one line from the config file and parses it as an IP address.

### n4c_parse_ip
Converts ASCII IP address (e.g., "192.168.1.1") to 4-byte binary format.

### n4c_parse_decimal
Parses a decimal number (0-255) from ASCII string.

### n4c_init_w5100
Writes configuration to W5100S registers.

### n4c_write_w5100_bytes
Writes multiple bytes to W5100S register space.

### n4c_print_ip
Displays an IP address in dotted decimal format.

### n4c_print_decimal
Displays a decimal number (0-255).

### n4c_print, n4c_print_char, n4c_print_crlf
Screen output routines.

## W5100S Registers Configured

The module initializes these W5100S registers:

| Register | Address | Description | Value From |
|----------|---------|-------------|------------|
| MR | 0x0000 | Mode Register | Set to 3 (auto-increment + indirect bus) |
| GAR | 0x0001-0x0004 | Gateway Address | Line 3 of N4C.CFG |
| SUBR | 0x0005-0x0008 | Subnet Mask | Line 2 of N4C.CFG |
| SIPR | 0x000F-0x0012 | Source IP | Line 1 of N4C.CFG |
| N_DNSIP | 0x0019-0x001C | DNS Server | Line 4 of N4C.CFG |

## Data Buffers

The module maintains these internal buffers:

- `n4c_ip_addr` (4 bytes) - Configured IP address
- `n4c_netmask` (4 bytes) - Configured netmask
- `n4c_gateway` (4 bytes) - Configured gateway
- `n4c_dns` (4 bytes) - Configured DNS server
- `n4c_line_buf` (32 bytes) - Temporary buffer for file reading

## Example Application

```z80
    org 0x8000

TXT_OUTPUT  equ 0xBB5A
SCR_SET_MODE equ 0xBC0E

start:
    ; Set screen mode
    ld a, 2
    call SCR_SET_MODE

    ; Initialize network
    call N4C_INIT
    jr c, error_exit

    ; Network is ready - do network operations
    ; ...

    ret

error_exit:
    ; Error already displayed by N4C_INIT
    ; A contains error code
    ret

    ; Include network library
    include "n4c-netinit.s"
    include "w5100.s"
    include "dns_simple.s"

SAVE 'MYAPP.BIN',#8000,$-#8000,AMSDOS
```

## Benefits for Application Developers

1. **Consistent Behavior** - All n4c-nettools applications work the same way
2. **User-Friendly** - Users configure once, use everywhere
3. **Less Code** - No need to write your own config parsing
4. **Error Handling** - Built-in validation and error messages
5. **Maintainable** - Config changes don't require recompiling

## Compatibility

- Works with all Amstrad CPC models (464/664/6128)
- Requires Net4CPC (W5100S) hardware
- Uses standard Amstrad firmware calls (CAS_IN_*, TXT_OUTPUT)
- No external dependencies beyond standard firmware

## Size

The n4c-netinit.s module adds approximately 800 bytes to your application binary.

## Future Enhancements

Potential future additions:
- Support for MAC address configuration
- DHCP client (dynamic IP allocation)
- Multiple network profiles
- Configuration validation and warnings

## See Also

- `CONFIG.md` - Configuration file documentation
- `N4C.CFG.example` - Example configuration file
- `w5100.s` - W5100S hardware driver
- `dns_simple.s` - DNS resolver
