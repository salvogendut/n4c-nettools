# N4C-NETTOOLS - Network Programming Library for Net4CPC

A collection of network utilities and libraries for the Amstrad CPC with Net4CPC (W5100S Ethernet) hardware.

## Overview

This library provides a complete Z80 assembly network stack for developing network applications on the Amstrad CPC with Net4CPC hardware. It includes low-level W5100S driver functions, DNS resolution, and example programs.

**Usage Model:** This is a reference library. Applications copy the files they need (w5100.s, dns_simple.s) into their own source directories to remain self-contained. Each application is independent and includes its own copy of the networking code.

## Hardware Requirements

- **Amstrad CPC** (464/664/6128)
- **Net4CPC** - W5100S Ethernet interface
- **I/O Ports:** 0xFD20-0xFD23 (W5100S access)

## Library Components

### Core Library (`src/`)

#### w5100.s - W5100S Hardware Interface Layer
Complete driver for W5100S Ethernet chip with socket-based networking.

**Functions:**
- `SOCKET` - Open TCP or UDP socket
- `CONNECT` - Connect TCP socket to remote host
- `CLOSE` - Close socket
- `SENDTO` - Send UDP datagram
- `SELECT` - Check socket status (readable/writable)
- `NET_SEND` - Send TCP data
- `NET_RECV` - Receive TCP data
- `CHECK_CONNECTION` - Verify TCP connection status
- `W5100_READ_REG` / `W5100_WRITE_REG` - Register access
- `W5100_READ_BUF` / `W5100_WRITE_BUF` - Buffer access
- `N_TIME` - Get timer value
- `N_DPRT` - Get dynamic port number
- `N_RIPA` - Read IP address from W5100S

**Socket Types:**
- `SK_STREAM` (1) - TCP socket
- `SK_DGRAM` (2) - UDP socket

**Select Types:**
- `SL_RECV` (1) - Check for received data
- `SL_SEND` (2) - Check if can send data

#### dns_simple.s - DNS Resolver
Simple DNS client implementing RFC 1034 for hostname resolution.

**Main Function:**
- `RESOLVE_HOSTNAME` - Resolve hostname to IP address
  - Entry: HL = hostname string (null-terminated)
  - Entry: DE = result buffer (4 bytes for IP)
  - Exit: Carry clear if OK, set on error
  - Exit: A = error code if carry set

**Error Codes:**
- 16 - SOCKET failed
- 18 - DNS query build failed
- 19 - SENDTO failed
- 20 - Timeout waiting for response
- 21 - Response has QR bit clear (not a response)
- 22 - DNS server returned error
- 23-27 - Parse errors

**Configuration:**
- DNS server IP must be configured in W5100S registers (via EWEN.BAS or setup code)
- Default timeout: 3000ms

## Examples

### DNS Test Program (`examples/dnstest.s`)

Standalone program to test DNS resolution. Resolves "google.com" and displays the IP address.

**Build:**
```bash
cd examples
./build_dnstest.sh
```

**Run on CPC:**
```basic
LOAD"DNS.BAS"
RUN
```

**Expected output:**
```
DNS Test Program
================
Resolving: google.com
DNS Server: 192.168.68.54
Success! IP: 198.178.203.100
```

## Using in Your Projects

### 1. Copy the Library Files

Copy the library files you need to your project's source directory:
```bash
cp n4c-nettools/src/w5100.s your-project/src/
cp n4c-nettools/src/dns_simple.s your-project/src/  # If you need DNS
```

Then in your main assembly file:
```z80
    include "w5100.s"
    include "dns_simple.s"
```

**Important:** Each application should have its own copy of these files. This keeps your project self-contained and buildable without external dependencies.

### 2. Initialize W5100S

At startup, set the mode register:
```z80
    ld bc, 0xFD20
    ld a, 3                     ; Auto-increment + indirect bus mode
    out (c), a
```

Network configuration (IP, gateway, DNS) should be done via BASIC setup program or initialization code.

### 3. Example: TCP Connection

```z80
    ; Resolve hostname
    ld hl, hostname             ; "example.com"
    ld de, ip_buffer
    call RESOLVE_HOSTNAME
    jp c, error_dns

    ; Create TCP socket
    ld a, 0                     ; Socket 0
    ld d, SK_STREAM             ; TCP
    ld e, 0
    call SOCKET
    jp c, error_socket

    ; Connect to server
    ld hl, ip_buffer
    ld bc, 80                   ; Port 80
    call CONNECT
    jp c, error_connect

    ; Send HTTP request
    ld hl, http_request
    ld bc, request_len
    call NET_SEND

    ; Receive response
    ld hl, response_buffer
    ld bc, 2048
    call NET_RECV

    ; Close connection
    call CLOSE

hostname:       db "example.com",0
ip_buffer:      ds 4
http_request:   db "GET / HTTP/1.0",13,10,13,10
request_len:    equ $-http_request
response_buffer: ds 2048
```

### 4. Example: UDP Datagram

```z80
    ; Create UDP socket
    ld a, 0xFF                  ; Auto-allocate socket
    ld d, SK_DGRAM              ; UDP
    ld e, 0
    call SOCKET
    jp c, error_socket
    ld (my_socket), a

    ; Build peer data (IP + port)
    ld hl, peer_data
    ld de, target_ip
    ld bc, 4
    ldir                        ; Copy IP
    ld (hl), 0                  ; Port MSB
    inc hl
    ld (hl), 53                 ; Port LSB (DNS = 53)

    ; Send datagram
    ld a, (my_socket)
    ld hl, udp_data
    ld bc, data_len
    ld de, peer_data
    call SENDTO
    jp c, error_send

    ; Close socket
    ld a, (my_socket)
    call CLOSE

my_socket:      db 0
peer_data:      ds 8            ; 4 IP + 2 port + 2 size
target_ip:      db 8,8,8,8      ; 8.8.8.8
udp_data:       db "Hello, UDP!"
data_len:       equ $-udp_data
```

## W5100S Register Map

### Common Registers
- `0x0000` - Mode Register (MR) - set to 3 for indirect bus + auto-increment
- `0x0001` - Gateway Address (GAR0-3)
- `0x0005` - Subnet Mask (SUBR0-3)
- `0x0009` - Source Hardware Address (SHAR0-5)
- `0x000F` - Source IP Address (SIPR0-3)
- `0x0019` - DNS Server IP (N_DNSIP)

### Socket Registers (Socket 0: base 0x0400, Socket 1: base 0x0500, etc.)
- `+0x00` - Mode (Sn_MR)
- `+0x01` - Command (Sn_CR)
- `+0x02` - Interrupt (Sn_IR)
- `+0x03` - Status (Sn_SR)
- `+0x04` - Source Port (Sn_PORT0-1)
- `+0x0C` - Destination IP (Sn_DIPR0-3)
- `+0x10` - Destination Port (Sn_DPORT0-1)
- `+0x20` - TX Free Size (Sn_TX_FSR0-1)
- `+0x24` - TX Write Pointer (Sn_TX_WR0-1)
- `+0x26` - RX Received Size (Sn_RX_RSR0-1)
- `+0x28` - RX Read Pointer (Sn_RX_RD0-1)

### Memory Buffers
- `0x4000-0x5FFF` - Socket TX buffers (2KB each)
- `0x6000-0x7FFF` - Socket RX buffers (2KB each)

## Applications Using This Library

- **n4cewenterm** - ANSI Telnet client with DNS support

## Future Additions

Planned utilities:
- FTP client
- Ping utility
- Simple HTTP client
- NTP time sync

## Technical Notes

### Known Issues and Bugs Fixed

1. **SENDTO destination registers** - Use byte-by-byte writes with W5100_WRITE_REG, not W5100_WRITE_BUF
2. **DNS name encoding** - Must save label counter to A before `pop bc` to avoid register overwrite
3. **Result buffer pointers** - Save DE before function calls that destroy it
4. **RX buffer reading** - Direct buffer access works better than complex RECVFR implementations

### Common Bug Patterns to Avoid

```z80
; WRONG - second LD overwrites H
ld h, a
ld hl, 0x1234

; RIGHT - use separate instructions or BC register
ld h, a
ld l, low_byte
ld h, high_byte

; WRONG - pop overwrites B before reading it
ld a, b                 ; B has important value
pop bc                  ; Now B is destroyed!
ld (dest), a           ; Wrong value

; RIGHT - save before pop
ld a, b                 ; Save B to A FIRST
pop bc                  ; Now safe to pop
ld (dest), a           ; Correct value
```

## Credits

- Based on KCNet DNS client by susowa (2008)
- Adapted for Net4CPC W5100S hardware (2026)
- Integrated into n4cewenterm project
- Debugging and bug fixes: Claude & User collaboration (2026-05-04/05)

## License

Open source - use freely in your own Amstrad CPC network projects.
