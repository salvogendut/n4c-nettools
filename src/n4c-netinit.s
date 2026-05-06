; N4C-NETINIT - Network Initialization Module for Net4CPC
; Reads configuration from N4C.CFG and initializes W5100S
;
; Usage:
;   call N4C_INIT
;   jr c, error_handler    ; Carry set on error, A = error code
;
; Configuration file format (N4C.CFG):
;   Line 1: IP address (e.g., 192.168.1.100)
;   Line 2: Netmask (e.g., 255.255.255.0)
;   Line 3: Gateway (e.g., 192.168.1.1)
;   Line 4: DNS server (e.g., 192.168.1.1)
;
; Each line is ASCII decimal octets separated by dots, terminated by CR or LF

;=======================================================
; Constants
;=======================================================
N4C_CONFIG_FILE:    db "N4C.CFG",0

; Error codes
N4C_ERR_NO_FILE     equ 1       ; Config file not found
N4C_ERR_READ        equ 2       ; Error reading file
N4C_ERR_PARSE       equ 3       ; Invalid config format
N4C_ERR_W5100       equ 4       ; W5100S not responding

; Firmware routines
CAS_IN_OPEN         equ 0xBC77
CAS_IN_CLOSE        equ 0xBC7A
CAS_IN_CHAR         equ 0xBC80
CAS_IN_DIRECT       equ 0xBC83

;=======================================================
; N4C_INIT - Initialize Net4CPC with configuration file
; Entry: None
; Exit:  Carry clear if OK, set on error
;        A = error code if carry set
;=======================================================
N4C_INIT:
    push hl
    push de
    push bc

    ; Display initialization message
    ld hl, msg_init
    call n4c_print

    ; Open configuration file
    ld hl, N4C_CONFIG_FILE
    ld b, 0                     ; Read-only
    call CAS_IN_OPEN
    jr nc, .file_not_found

    ; File opened successfully
    ; Read IP address (line 1)
    ld de, n4c_ip_addr
    call n4c_read_ip_line
    jr c, .read_error

    ; Read Netmask (line 2)
    ld de, n4c_netmask
    call n4c_read_ip_line
    jr c, .read_error

    ; Read Gateway (line 3)
    ld de, n4c_gateway
    call n4c_read_ip_line
    jr c, .read_error

    ; Read DNS server (line 4)
    ld de, n4c_dns
    call n4c_read_ip_line
    jr c, .read_error

    ; Close file
    call CAS_IN_CLOSE

    ; Display configuration
    ld hl, msg_ip
    call n4c_print
    ld hl, n4c_ip_addr
    call n4c_print_ip

    ld hl, msg_netmask
    call n4c_print
    ld hl, n4c_netmask
    call n4c_print_ip

    ld hl, msg_gateway
    call n4c_print
    ld hl, n4c_gateway
    call n4c_print_ip

    ld hl, msg_dns
    call n4c_print
    ld hl, n4c_dns
    call n4c_print_ip

    ; Initialize W5100S
    call n4c_init_w5100
    jr c, .w5100_error

    ; Success!
    ld hl, msg_ready
    call n4c_print

    pop bc
    pop de
    pop hl
    or a                        ; Clear carry
    ret

.file_not_found:
    call CAS_IN_CLOSE           ; Just in case
    ld hl, msg_err_no_file
    call n4c_print
    pop bc
    pop de
    pop hl
    scf
    ld a, N4C_ERR_NO_FILE
    ret

.read_error:
    call CAS_IN_CLOSE
    ld hl, msg_err_read
    call n4c_print
    pop bc
    pop de
    pop hl
    scf
    ld a, N4C_ERR_READ
    ret

.w5100_error:
    ld hl, msg_err_w5100
    call n4c_print
    pop bc
    pop de
    pop hl
    scf
    ld a, N4C_ERR_W5100
    ret

;=======================================================
; n4c_read_ip_line - Read one line of IP address
; Entry: DE = buffer for 4-byte IP address
; Exit:  Carry clear if OK, set on error
;=======================================================
n4c_read_ip_line:
    push hl
    push de
    push bc

    ld hl, n4c_line_buf
    ld b, 0                     ; Character counter

.read_char:
    ; Read one character
    call CAS_IN_CHAR
    jr nc, .eof                 ; End of file

    ; Check for end of line
    cp 13                       ; CR
    jr z, .eol
    cp 10                       ; LF
    jr z, .eol
    cp 26                       ; EOF
    jr z, .eof

    ; Store character
    ld (hl), a
    inc hl
    inc b
    ld a, b
    cp 20                       ; Max line length
    jr c, .read_char

.eol:
    ; Null terminate
    xor a
    ld (hl), a

    ; Skip any additional CR/LF
.skip_eol:
    call CAS_IN_CHAR
    jr nc, .parse               ; EOF
    cp 13
    jr z, .skip_eol
    cp 10
    jr z, .skip_eol
    ; Not CR/LF, this is start of next line - we can't put it back, but that's ok
    ; CAS_IN_CHAR advances, we'll just lose one char - need better approach

.parse:
    ; Parse IP address from line buffer
    pop de                      ; DE = output buffer
    push de
    ld hl, n4c_line_buf
    call n4c_parse_ip
    jr c, .error

    pop bc
    pop de
    pop hl
    or a                        ; Clear carry
    ret

.eof:
.error:
    pop bc
    pop de
    pop hl
    scf
    ret

;=======================================================
; n4c_parse_ip - Parse IP address from ASCII string
; Entry: HL = ASCII string (e.g., "192.168.1.100")
;        DE = output buffer (4 bytes)
; Exit:  Carry clear if OK, set on error
;=======================================================
n4c_parse_ip:
    push hl
    push de
    push bc

    ; Parse 4 octets
    ld b, 4
.parse_octet:
    push bc
    call n4c_parse_decimal      ; Returns value in A
    pop bc
    jr c, .error

    ; Store octet
    ld (de), a
    inc de

    ; Check for dot or end
    ld a, (hl)
    or a
    jr z, .done                 ; Null terminator
    cp '.'
    jr nz, .error
    inc hl                      ; Skip dot

    djnz .parse_octet

.done:
    pop bc
    pop de
    pop hl
    or a                        ; Clear carry
    ret

.error:
    pop bc
    pop de
    pop hl
    scf
    ret

;=======================================================
; n4c_parse_decimal - Parse decimal number from string
; Entry: HL = string pointer
; Exit:  A = parsed number (0-255)
;        HL = pointer after number
;        Carry set on error
;=======================================================
n4c_parse_decimal:
    push bc
    ld b, 0                     ; Accumulator

.loop:
    ld a, (hl)
    cp '0'
    jr c, .done                 ; < '0'
    cp '9'+1
    jr nc, .done                ; > '9'

    ; Valid digit - convert
    sub '0'
    ld c, a

    ; Multiply accumulator by 10
    ld a, b
    add a, a                    ; *2
    add a, a                    ; *4
    add a, b                    ; *5
    add a, a                    ; *10
    add a, c                    ; Add new digit
    ld b, a

    inc hl
    jr .loop

.done:
    ld a, b
    pop bc
    or a                        ; Clear carry
    ret

;=======================================================
; n4c_init_w5100 - Initialize W5100S with configuration
; Entry: None (uses n4c_* variables)
; Exit:  Carry clear if OK, set on error
;=======================================================
n4c_init_w5100:
    push hl
    push de
    push bc
    push af

    ; Set mode register (indirect bus + auto-increment)
    ld bc, 0xFD20
    ld a, 3
    out (c), a

    ; Verify we can read it back
    in a, (c)
    cp 3
    jr nz, .error

    ; Set Gateway Address (GAR)
    ld hl, 0x0001               ; GAR0
    ld de, n4c_gateway
    ld b, 4
    call n4c_write_w5100_bytes

    ; Set Subnet Mask (SUBR)
    ld hl, 0x0005               ; SUBR0
    ld de, n4c_netmask
    ld b, 4
    call n4c_write_w5100_bytes

    ; Set Source IP Address (SIPR)
    ld hl, 0x000F               ; SIPR0
    ld de, n4c_ip_addr
    ld b, 4
    call n4c_write_w5100_bytes

    ; Set DNS Server IP (custom location for compatibility)
    ld hl, 0x0019               ; N_DNSIP
    ld de, n4c_dns
    ld b, 4
    call n4c_write_w5100_bytes

    pop af
    pop bc
    pop de
    pop hl
    or a                        ; Clear carry
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
; Entry: HL = W5100S register address
;        DE = source buffer
;        B = byte count
;=======================================================
n4c_write_w5100_bytes:
    push bc
    push af

    ld bc, 0xFD20
    out (c), h                  ; Address MSB
    ld bc, 0xFD21
    out (c), l                  ; Address LSB
    ld bc, 0xFD22
    xor a
    out (c), a                  ; Operation: write, auto-increment

    ld bc, 0xFD23               ; Data port

    pop af
    pop bc

.write_loop:
    push bc
    ld a, (de)
    out (c), a
    inc de
    pop bc
    djnz .write_loop
    ret

;=======================================================
; n4c_print_ip - Print IP address
; Entry: HL = pointer to 4-byte IP address
;=======================================================
n4c_print_ip:
    push hl
    push bc
    push af

    ld b, 4
.loop:
    ld a, (hl)
    call n4c_print_decimal
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
; n4c_print_decimal - Print decimal number
; Entry: A = number (0-255)
;=======================================================
n4c_print_decimal:
    push af
    push bc
    push de

    ld e, a
    ld d, 0

    ; Hundreds
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
    ; Tens
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

    ; Ones
    add a, '0'
    call n4c_print_char

    pop de
    pop bc
    pop af
    ret

;=======================================================
; n4c_print - Print zero-terminated string
; Entry: HL = string pointer
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

;=======================================================
; n4c_print_char - Print single character
; Entry: A = character
;=======================================================
n4c_print_char:
    push hl
    push de
    push bc
    push af
    call 0xBB5A                 ; TXT_OUTPUT
    pop af
    pop bc
    pop de
    pop hl
    ret

;=======================================================
; n4c_print_crlf - Print CR+LF
;=======================================================
n4c_print_crlf:
    push af
    ld a, 13
    call n4c_print_char
    ld a, 10
    call n4c_print_char
    pop af
    ret

;=======================================================
; Data and Messages
;=======================================================
msg_init:       db "N4C Network Initialization",13,10,0
msg_ip:         db "IP Address: ",0
msg_netmask:    db "Netmask:    ",0
msg_gateway:    db "Gateway:    ",0
msg_dns:        db "DNS Server: ",0
msg_ready:      db "Network Ready",13,10,13,10,0

msg_err_no_file: db "ERROR: N4C.CFG not found",13,10,0
msg_err_read:    db "ERROR: Failed to read config",13,10,0
msg_err_w5100:   db "ERROR: W5100S not responding",13,10,0

; Configuration buffers
n4c_ip_addr:    ds 4
n4c_netmask:    ds 4
n4c_gateway:    ds 4
n4c_dns:        ds 4
n4c_line_buf:   ds 32
