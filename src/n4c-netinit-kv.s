; N4C-NETINIT-KV - Network initialization for Net4CPC
;
; USB/FAT build (-DAMSDOS_USB=1): N4C_INIT reads N4C.CFG from disc and parses it.
; Standard AMSDOS build: N4C_INIT uses config pre-loaded into RAM by the BASIC
;   loader.  The .BAS file reads N4C.CFG via OPENIN and POKEs 16 bytes starting
;   at N4C_CFG_BASE (&3F10):
;     &3F10 IP[0..3]   &3F14 MASK[0..3]   &3F18 GW[0..3]   &3F1C DNS[0..3]

;=======================================================
; Firmware vectors (CAS IN)
;=======================================================
IFDEF AMSDOS_USB
; USB/FAT Unidos roms (Albireo/GoTek): CAS IN +3 from standard
CAS_IN_OPEN         equ 0xBC77
CAS_IN_CLOSE        equ 0xBC7A
CAS_IN_CHAR         equ 0xBC80
CAS_IN_DIRECT       equ 0xBC83
ENDIF

;=======================================================
; N4C_INIT - Initialize network
;=======================================================
N4C_INIT:
    push hl
    push de
    push bc

IFDEF AMSDOS_USB
    ; Open N4C.CFG from disc
    ld hl, N4C_CONFIG_FILENAME
    ld b, 7
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
    ; First byte 0xFF means AMSDOS header prepended — shift content down by 1
    ld a, (file_buffer)
    cp 0xFF
    jr nz, .eof

    push bc
    ld a, b
    or a
    jr z, .skip_shift
    ld hl, file_buffer+1
    ld de, file_buffer
    ld a, b
    dec a
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

    ; Parse each key=value field
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

ENDIF   ; AMSDOS_USB
        ; Standard build: config already in RAM at N4C_CFG_BASE, fall through

    ; Initialize W5100S
    call n4c_init_w5100
    jr c, .w5100_error

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

IFDEF AMSDOS_USB
.file_not_found:
    ld hl, msg_err_no_file
    call n4c_print
    pop bc
    pop de
    pop hl
    scf
    ret

;=======================================================
; find_and_parse - Find key in buffer and parse IP value
; Entry: HL = buffer, DE = key string, BC = destination
;=======================================================
find_and_parse:
    push bc

.scan_line:
    push hl
    call match_key
    jr z, .found_key

    pop hl
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
    pop af
    inc hl          ; skip '='
    pop bc
    push bc

    ld ix, 0
    add ix, bc
    ld b, 4
.octet_loop:
    call parse_decimal_byte
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
; match_key - Match key at DE against text at HL
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
    cp 61           ; '='
    ret

ENDIF   ; AMSDOS_USB

;=======================================================
; parse_decimal_byte - Parse decimal number at HL
; Exit: A = value, HL advanced past digits
; (used by both builds: find_and_parse and wget.s PARSE_DOTTED_IP)
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
; n4c_init_w5100 - Write config into W5100S registers
;=======================================================
n4c_init_w5100:
    push hl
    push de
    push bc
    push af

    ; Verify mode register
    ld bc, 0xFD20
    in a, (c)
    cp 3
    jr nz, .error

    ld hl, 0x0009
    ld de, n4c_mac_addr
    ld b, 6
    call n4c_write_w5100_bytes

    ld hl, 0x0001
    ld de, n4c_gateway
    ld b, 4
    call n4c_write_w5100_bytes

    ld hl, 0x0005
    ld de, n4c_netmask
    ld b, 4
    call n4c_write_w5100_bytes

    ld hl, 0x000F
    ld de, n4c_ip_addr
    ld b, 4
    call n4c_write_w5100_bytes

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
; n4c_write_w5100_bytes - Write B bytes from (DE) to W5100S
; Entry: HL = register address, DE = source, B = count
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

;=======================================================
; Data
;=======================================================
IFDEF AMSDOS_USB
N4C_CONFIG_FILENAME: db "N4C.CFG",0
key_ip:     db "IP",0
key_mask:   db "MASK",0
key_gw:     db "GW",0
key_dns:    db "DNS",0
msg_err_no_file: db "ERROR: N4C.CFG not found",13,10,0
ENDIF

msg_err_w5100:  db "ERROR: W5100S not responding",13,10,0

n4c_mac_addr:   db 0xDE,0xAD,0xBE,0xEF,0x00,0xFF

IFDEF AMSDOS_USB
; Config populated by N4C_INIT from disc
n4c_ip_addr:    ds 4
n4c_netmask:    ds 4
n4c_gateway:    ds 4
n4c_dns:        ds 4
file_buffer:    ds 128
ELSE
; Config populated by BASIC loader (POKE to these fixed addresses before CALL)
N4C_CFG_BASE    equ 0x3F10
n4c_ip_addr     equ N4C_CFG_BASE+0
n4c_netmask     equ N4C_CFG_BASE+4
n4c_gateway     equ N4C_CFG_BASE+8
n4c_dns         equ N4C_CFG_BASE+12
ENDIF
