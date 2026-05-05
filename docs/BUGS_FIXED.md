# Bugs Fixed During DNS Development

This document catalogs the 9 critical bugs discovered and fixed during the development of the DNS resolver for Net4CPC.

## Bug #1: Hostname Copy Bug (CRITICAL)

**Symptom:** DNS query had empty hostname (00 bytes instead of encoded "google.com"), query was only 18 bytes instead of 28.

**Root Cause:** RESOLVE_HOSTNAME stack manipulation caused `dns_strcpy` to copy from wrong memory location (result buffer instead of hostname pointer).

**Fix:** Simplified stack operations:
```z80
; WRONG - complex stack manipulation loses hostname pointer
push hl
push de
push bc
; ... various operations ...
call dns_strcpy  ; Wrong pointer!

; RIGHT - pop all, get correct pointers, call function
pop bc                      ; BC = saved BC
pop de                      ; DE = result buffer  
pop hl                      ; HL = hostname pointer
push de                     ; Save result buffer
push bc                     ; Save BC
ld de, dns_hostname_buf
call dns_strcpy             ; Correct pointer!
```

**Impact:** Without this fix, DNS queries were malformed and DNS server would reject them.

---

## Bug #2: DNS Name Encoding Bug (CRITICAL)

**Symptom:** Label length bytes were 00 instead of actual character count. "google.com" encoded as `00 67 6f 6f 67 6c 65 00 63 6f 6d 00` instead of `06 67 6f 6f 67 6c 65 03 63 6f 6d 00`.

**Root Cause:** B register held character counter, but `pop bc` overwrote B before `ld a, b` could read it.

**Fix:** Save counter to A before popping BC:
```z80
; WRONG - B gets overwritten before we read it
.end_label:
    pop bc                      ; BC = label length position
    ld a, b                     ; BUG: B already destroyed!
    
; RIGHT - save B to A FIRST
.end_label:
    ld a, b                     ; Save counter to A FIRST
    pop bc                      ; Now safe to pop
    push hl
    ld h, b
    ld l, c
    ld (hl), a                  ; Write correct length
    pop hl
```

**Impact:** DNS queries had invalid name encoding, causing DNS server to reject queries or return errors.

---

## Bug #3: SENDTO Destination Bug (CRITICAL)

**Symptom:** W5100S destination registers showed wrong values. S1_DIPR showed `00 00 00 00` instead of `C0 A8 44 36` (192.168.68.54), S1_DPORT showed `B901` instead of `00 35` (port 53).

**Root Cause:** W5100_WRITE_BUF wasn't working reliably for setting W5100S destination registers.

**Fix:** Rewrote SENDTO to write each byte individually using W5100_WRITE_REG:
```z80
; WRONG - bulk write doesn't work for destination registers
ld hl, S1_DIPR0
ld de, peer_data
ld bc, 6
call W5100_WRITE_BUF        ; Unreliable!

; RIGHT - write each byte individually
ld hl, (sendto_peer_ptr)
ld a, (hl)                  ; IP byte 0
push hl
ld hl, S1_DIPR0
call W5100_WRITE_REG
pop hl
inc hl
; ... repeat for all 6 bytes (4 IP + 2 port)
```

**Impact:** UDP packets were sent to wrong destination (0.0.0.0:47361 instead of 192.168.68.54:53), so DNS server never received queries. Fixing this changed error code from 11 (no data) to 10 (data available).

---

## Bug #4: RECVFR Crash Bug

**Symptom:** System crashed with yellow screen or froze/rebooted when receiving DNS response.

**Root Cause:** Original RECVFR had complex pointer arithmetic that corrupted memory.

**Fix:** Replaced RECVFR with simple direct W5100S RX buffer read:
```z80
; Get RX_RD pointer
ld hl, 0x0528               ; S1_RX_RD0
call W5100_READ_REG
ld d, a
ld hl, 0x0529
call W5100_READ_REG
ld e, a                     ; DE = RX_RD

; Skip 8-byte UDP header
ld hl, 8
add hl, de

; Mask to buffer size and add base
ld a, e
and 0xFF
ld l, a
ld a, d
and 0x07                    ; Mask to 2KB
ld h, a
ld de, 0x6800               ; S1_RX_BASE
add hl, de

; Read 64 bytes
ex de, hl
ld hl, dns_response_buf
ld bc, 64
call W5100_READ_BUF

; Update RX_RD and issue RECV command
; ...
```

**Impact:** Eliminated all crashes when receiving UDP data.

---

## Bug #5: DNS Parse Offset Bug

**Symptom:** Error 23 (answer name not a pointer) when parsing DNS response.

**Root Cause:** dns_parse_response was skipping to byte 13 instead of byte 12 (question section start).

**Fix:** Changed from double `inc hl` to single `inc hl`:
```z80
; WRONG - skips too far
ld bc, 8
add hl, bc                  ; HL at byte 11
inc hl                      ; byte 12
inc hl                      ; byte 13 - TOO FAR!

; RIGHT - skip to correct offset
ld bc, 8
add hl, bc                  ; HL at byte 11
inc hl                      ; byte 12 - CORRECT!
```

**Impact:** DNS response parsing now finds question section correctly and can skip to answer section.

---

## Bug #6: W5100_READ_BUF Parameter Swap Bug

**Symptom:** System freeze with screen corruption after "skipping call".

**Root Cause:** Called W5100_READ_BUF with swapped parameters. Function expects (HL=host buffer, DE=W5100S addr) but was called with (HL=W5100S addr, DE=host buffer).

**Fix:** Swapped parameter order in call:
```z80
; WRONG - parameters backwards
ld hl, w5100s_address       ; W5100S address
ld de, host_buffer          ; Host buffer
call W5100_READ_BUF         ; WRONG ORDER!

; RIGHT - correct parameter order
ld de, w5100s_address       ; W5100S address
ld hl, host_buffer          ; Host buffer
call W5100_READ_BUF         ; Correct!
```

**Impact:** Eliminated memory corruption and system freezes.

---

## Bug #7: dns_peer_data Buffer Too Small

**Symptom:** Buffer overrun when RECVFR wrote peer data.

**Root Cause:** Allocated 6 bytes but RECVFR needs 8 bytes (4 IP + 2 port + 2 size).

**Fix:** Changed buffer size:
```z80
; WRONG - too small
dns_peer_data:      ds 6

; RIGHT - correct size
dns_peer_data:      ds 8        ; 4 bytes IP + 2 bytes port + 2 bytes size
```

**Impact:** Ultimately bypassed by replacing RECVFR, but the fix prevented potential buffer overrun issues.

---

## Bug #8: Timeout Wraparound Bug

**Symptom:** Error 20 (timeout) after only 10 wait loops instead of waiting full timeout period.

**Root Cause:** Start time FFEC + timeout 3000 wrapped around to 0BA4, causing immediate timeout check to succeed.

**Fix:** Calculate elapsed time instead of target time:
```z80
; WRONG - wraparound when start_time + timeout > FFFF
call N_TIME
ld (start_time), hl         ; e.g., FFEC
ld de, 3000
add hl, de                  ; FFEC + 3000 = 0BA4 (wrapped!)
ld (timeout_time), hl
; Later...
call N_TIME                 ; e.g., FFED
ld de, (timeout_time)       ; 0BA4
sbc hl, de                  ; FFED - 0BA4 = huge number - timeout!

; RIGHT - calculate elapsed time
call N_TIME
ld (start_time), hl         ; e.g., FFEC
; Later...
call N_TIME                 ; e.g., FFED
ld de, (start_time)         ; FFEC
or a
sbc hl, de                  ; FFED - FFEC = 1 (correct!)
ld de, DNS_TIMEOUT          ; 3000
or a
sbc hl, de                  ; 1 - 3000 = negative, keep waiting
```

**Impact:** Timeout now works correctly even when timer wraps around.

---

## Bug #9: Result Buffer Pointer Bug (CRITICAL - Integration)

**Symptom:** All DNS lookups returned 127.0.0.1 instead of actual resolved IP. Discovered when telnet client tried to resolve "aardwolf.org".

**Root Cause:** RESOLVE_HOSTNAME ignored the DE parameter (result buffer pointer) and always wrote to hardcoded `result_ip_temp` buffer. DE register gets overwritten by SOCKET/SENDTO calls before dns_parse_response.

**Fix:** Save DE to variable before it gets destroyed:
```z80
; At start of RESOLVE_HOSTNAME, after getting parameters:
pop bc
pop de                      ; DE = result buffer
pop hl                      ; HL = hostname
ld (dns_result_ptr), de     ; SAVE IT!

; Much later, before parsing:
ld de, (dns_result_ptr)     ; RESTORE IT!
call dns_parse_response     ; Now writes to correct buffer

; Add variable:
dns_result_ptr:     dw 0
```

**Impact:** DNS resolver now writes IP address to caller's buffer instead of internal temp buffer. Critical for telnet integration.

---

## Common Bug Patterns

### Pattern 1: Register Overwrite

```z80
; BAD - second ld overwrites H
ld h, a
ld hl, 0x1234

; GOOD - use BC or separate loads
ld h, a
ld l, low_byte
ld h, high_byte
```

### Pattern 2: Pop Before Read

```z80
; BAD - pop destroys B before we read it
ld a, b
pop bc
ld (dest), a        ; Wrong value!

; GOOD - read BEFORE pop
ld a, b             ; Save to A FIRST
pop bc              ; Now safe
ld (dest), a        ; Correct value
```

### Pattern 3: Parameter Order

Always check function signatures carefully:
```z80
; W5100_READ_BUF expects:
; HL = host buffer
; DE = W5100S address
; BC = length

; Don't swap them!
```

### Pattern 4: Pointer Lifetimes

If a register holds an important pointer/value, and you need to call functions that destroy that register, save it first:
```z80
; DE has result buffer pointer
ld (saved_de), de           ; Save it!
call SOCKET                 ; Destroys DE
ld de, (saved_de)           ; Restore it!
call dns_parse_response     ; Use it
```

---

## Debugging Methodology Used

1. **Incremental marker testing** - Set debug markers at each step, return early with test error codes
2. **W5100S register verification** - Read back registers after writing to verify
3. **Packet inspection** - Display raw bytes to verify protocol correctness
4. **Progressive testing** - Test each function independently before combining

This systematic approach allowed finding all 9 bugs methodically rather than through trial and error.
