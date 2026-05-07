; N4C-NETINIT - SIMPLE COUNT TEST
; Just count how many bytes we can read from N4C.CFG

;=======================================================
; Constants
;=======================================================
N4C_CONFIG_FILENAME: db "N4C.CFG",0

; Firmware routines
CAS_IN_OPEN         equ 0xBC77
CAS_IN_CLOSE        equ 0xBC7A
CAS_IN_CHAR         equ 0xBC80
CAS_IN_DIRECT       equ 0xBC83

;=======================================================
; N4C_INIT - Count bytes in N4C.CFG
;=======================================================
N4C_INIT:
    push hl
    push de
    push bc

    ; Open file - NO messages while file is open!
    ld hl, N4C_CONFIG_FILENAME
    ld b, 7                     ; CAS_IN_OPEN needs B = filename length
    call CAS_IN_OPEN
    jp nc, .file_not_found

    ; Read entire file into temp area
    ld hl, file_buffer
    ld b, 0

.read_loop:
    call CAS_IN_DIRECT
    jr nc, .read_done

    ld (hl), a
    inc hl
    inc b
    jr .read_loop

.read_done:
    ; Check if first byte is FF (corrupted)
    ; Only shift if it is
    ld a, (file_buffer)
    cp 0xFF
    jr nz, .eof             ; First byte is good, no shift needed

    ; First byte is FF, shift everything down by 1
    push bc
    ld a, b
    or a
    jr z, .skip_shift

    ld hl, file_buffer+1    ; Source
    ld de, file_buffer      ; Dest
    ld a, b
    dec a                   ; Count = bytes - 1
    ld b, a

.shift_loop:
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    djnz .shift_loop

.skip_shift:
    pop bc

.eof:
    call CAS_IN_CLOSE

    ; Parse each field using key=value format
    ld hl, file_buffer
    ld de, key_ip
    ld bc, n4c_ip_addr
    call find_and_parse

    ld hl, file_buffer
    ld de, key_mask
    ld bc, n4c_netmask
    call find_and_parse

    ld hl, file_buffer
    ld de, key_gw
    ld bc, n4c_gateway
    call find_and_parse

    ld hl, file_buffer
    ld de, key_dns
    ld bc, n4c_dns
    call find_and_parse

    ; Display configuration (commented out for cleaner startup)
    ; ld hl, msg_ip
    ; call n4c_print
    ; ld hl, n4c_ip_addr
    ; call print_ip

    ; ld hl, msg_netmask
    ; call n4c_print
    ; ld hl, n4c_netmask
    ; call print_ip

    ; ld hl, msg_gateway
    ; call n4c_print
    ; ld hl, n4c_gateway
    ; call print_ip

    ; ld hl, msg_dns
    ; call n4c_print
    ; ld hl, n4c_dns
    ; call print_ip

    ; Initialize W5100S
    call n4c_init_w5100
    jr c, .w5100_error

    ; Network initialization successful - no output for cleaner startup
    ; ld hl, msg_ready
    ; call n4c_print

    ; ld hl, msg_press_key
    ; call n4c_print
    ; call 0xBB18             ; Wait for key

    pop bc
    pop de
    pop hl
    or a
    ret

.w5100_error:
    ld hl, msg_err_w5100
    call n4c_print
    pop bc
    pop de
    pop hl
    scf
    ret

.file_not_found:
    ld hl, msg_err_no_file
    call n4c_print
    pop bc
    pop de
    pop hl
    scf
    ret

;=======================================================
; find_and_parse - Find key in buffer and parse value
; Entry: HL = buffer, DE = key string, BC = destination
;=======================================================
find_and_parse:
    push bc                     ; Save destination

.scan_line:
    push hl                     ; Save line start position
    call match_key              ; Z if matched, HL points after key
    jr z, .found_key            ; If found, HL already at '='

    pop hl                      ; Restore line start
    ; Skip to next line
.skip_eol:
    ld a, (hl)
    or a
    jr z, .not_found
    inc hl
    cp 13
    jr z, .skip_lf
    cp 10
    jr nz, .skip_eol
    jr .scan_line

.skip_lf:
    ld a, (hl)
    cp 10
    jr nz, .scan_line
    inc hl
    jr .scan_line

.not_found:
    pop bc
    ret

.found_key:
    pop af                      ; Discard saved line start
    inc hl                      ; Skip '='
    pop bc                      ; BC = destination
    push bc

    ; Parse 4 octets
    ld ix, 0
    add ix, bc
    ld b, 4

.octet_loop:
    call parse_decimal_byte     ; A = octet
    ld (ix+0), a
    inc ix
    djnz .check_dot
    jr .done

.check_dot:
    ld a, (hl)
    cp '.'
    jr nz, .done
    inc hl
    jr .octet_loop

.done:
    pop bc
    ret

;=======================================================
; match_key - Compare key at DE with text at HL
; Exit: Z if matched, HL points at char after key
;=======================================================
match_key:
.loop:
    ld a, (de)
    or a
    jr z, .matched
    ld b, a
    ld a, (hl)
    cp b
    ret nz
    inc hl
    inc de
    jr .loop

.matched:
    ld a, (hl)
    cp 61                       ; '=' character
    ret

;=======================================================
; parse_decimal_byte - Parse decimal number
; Entry: HL = buffer position
; Exit: A = number, HL advanced
;=======================================================
parse_decimal_byte:
    ld d, 0

.loop:
    ld a, (hl)
    sub '0'
    jr c, .done
    cp 10
    jr nc, .done

    ld e, a
    ld a, d
    add a, a
    ld d, a
    add a, a
    add a, a
    add a, d
    add a, e
    ld d, a

    inc hl
    jr .loop

.done:
    ld a, d
    ret

;=======================================================
; n4c_init_w5100 - Initialize W5100S
;=======================================================
n4c_init_w5100:
    push hl
    push de
    push bc
    push af

    ; Check mode register
    ld bc, 0xFD20
    in a, (c)
    cp 3
    jr nz, .error

    ; Set MAC
    ld hl, 0x0009
    ld de, n4c_mac_addr
    ld b, 6
    call n4c_write_w5100_bytes

    ; Set Gateway
    ld hl, 0x0001
    ld de, n4c_gateway
    ld b, 4
    call n4c_write_w5100_bytes

    ; Set Netmask
    ld hl, 0x0005
    ld de, n4c_netmask
    ld b, 4
    call n4c_write_w5100_bytes

    ; Set IP
    ld hl, 0x000F
    ld de, n4c_ip_addr
    ld b, 4
    call n4c_write_w5100_bytes

    ; Set DNS
    ld hl, 0x0032
    ld de, n4c_dns
    ld b, 4
    call n4c_write_w5100_bytes

    pop af
    pop bc
    pop de
    pop hl
    or a
    ret

.error:
    pop af
    pop bc
    pop de
    pop hl
    scf
    ret

;=======================================================
; n4c_write_w5100_bytes - Write bytes to W5100S
;=======================================================
n4c_write_w5100_bytes:
.loop:
    push bc
    push hl

    ld bc, 0xFD21
    out (c), h
    ld bc, 0xFD22
    out (c), l

    ld bc, 0xFD23
    ld a, (de)
    out (c), a

    pop hl
    inc hl
    inc de
    pop bc
    djnz .loop
    ret

;=======================================================
; print_ip - Print IP address
; Entry: HL = pointer to 4 bytes
;=======================================================
print_ip:
    push hl
    push bc
    push af

    ld b, 4
.loop:
    ld a, (hl)
    call print_decimal
    inc hl
    dec b
    jr z, .done
    ld a, '.'
    call n4c_print_char
    jr .loop

.done:
    call n4c_print_crlf
    pop af
    pop bc
    pop hl
    ret

;=======================================================
; print_decimal - Print 0-255
;=======================================================
print_decimal:
    push af
    push bc
    push de

    ld e, a
    ld d, 0

    ld bc, 100
    ld a, e
.div_100:
    cp c
    jr c, .done_100
    sub c
    inc d
    jr .div_100

.done_100:
    ld e, a
    ld a, d
    or a
    jr z, .skip_100
    add a, '0'
    call n4c_print_char

.skip_100:
    ld a, e
    ld d, 0
.div_10:
    cp 10
    jr c, .done_10
    sub 10
    inc d
    jr .div_10

.done_10:
    push af
    ld a, d
    add a, '0'
    call n4c_print_char
    pop af
    add a, '0'
    call n4c_print_char

    pop de
    pop bc
    pop af
    ret

;=======================================================
; Print routines
;=======================================================
n4c_print:
    push af
    push hl
.loop:
    ld a, (hl)
    or a
    jr z, .done
    call n4c_print_char
    inc hl
    jr .loop
.done:
    pop hl
    pop af
    ret

n4c_print_char:
    push hl
    push de
    push bc
    push af
    call 0xBB5A
    pop af
    pop bc
    pop de
    pop hl
    ret

n4c_print_crlf:
    push af
    ld a, 13
    call n4c_print_char
    ld a, 10
    call n4c_print_char
    pop af
    ret

print_hex8:
    push af
    rrca
    rrca
    rrca
    rrca
    call print_hex4
    pop af
    call print_hex4
    ret

print_hex4:
    and 0x0F
    cp 10
    jr c, .digit
    add a, 'A' - 10
    jr .print
.digit:
    add a, '0'
.print:
    call n4c_print_char
    ret

;=======================================================
; Data
;=======================================================
key_ip:     db "IP",0
key_mask:   db "MASK",0
key_gw:     db "GW",0
key_dns:    db "DNS",0

msg_ip:         db "IP Address: ",0
msg_netmask:    db "Netmask:    ",0
msg_gateway:    db "Gateway:    ",0
msg_dns:        db "DNS Server: ",0
msg_ready:      db "Network Ready",13,10,0
msg_press_key:  db "Press any key...",13,10,0
msg_err_no_file:    db "ERROR: N4C.CFG not found",13,10,0
msg_err_w5100:  db "ERROR: W5100S not responding",13,10,0

buffer_write_ptr: dw 0
n4c_mac_addr:   db 0xDE,0xAD,0xBE,0xEF,0x00,0xFF
n4c_ip_addr:    ds 4
n4c_netmask:    ds 4
n4c_gateway:    ds 4
n4c_dns:        ds 4
dummy_byte:     db 0            ; RIGHT BEFORE file_buffer
file_buffer:    ds 128
