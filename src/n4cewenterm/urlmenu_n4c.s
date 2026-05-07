; URL/IP input menu for Net4CPC
; With DNS lookup support using KCNet DNS client

loop_ip:
    call drawline
    ld hl, msgserverip
    call disptextz
    call get_server
    cp 0
    jr nz, loop_ip

    ld hl, msgconnecting
    call disptextz

    ld hl, ip_addr
    call disp_ip

    ld hl, msgport
    call disptextz

    ld hl, (port)
    call disp_port
    call crlf
    call telnet_session
    jp loop_ip

print_lownib:
    and 0xF
    add 48
    jp printchar

get_server:
    ld hl, buf
    call get_textinput

    xor a
    cp c
    jr z, get_server

    ; Debug: show what was entered
    push bc
    ld hl, msgdebug_input
    call disptextz
    ld hl, buf
    call disptextz
    call crlf
    pop bc

    ; Check if it's all numeric (IP address) or contains letters (domain)
    ld b, c
    ld hl, buf

check_numeric:
    ld a, (hl)
    cp ':'              ; Port separator is OK
    jr z, .next_char
    cp '.'              ; Dot is OK for IP
    jr z, .next_char
    cp '0'
    jr c, do_lookup     ; < '0' means not numeric
    cp '9'+1
    jr nc, do_lookup    ; > '9' means not numeric

.next_char:
    inc hl
    djnz check_numeric

    ; All numeric - parse as IP
    ld hl, msgdebug_parseip
    call disptextz
    call crlf
    jp convert_ip

do_lookup:
    ; Debug
    ld hl, msgdebug_dns
    call disptextz
    call crlf
    ; Contains non-numeric chars - do DNS lookup
    ld hl, buf
    ld de, lookup_name
    ld b, 0

.copy_dns:
    ld a, (hl)
    cp ':'
    jr z, .copydns_done
    cp 0
    jr z, .copydns_done
    ld (de), a
    inc hl
    inc de
    inc b
    jr .copy_dns

.copydns_done:
    push hl             ; Save position (for port parsing)
    xor a
    ld (de), a          ; Null terminate

    ; Display what we're resolving
    ld hl, msgresolve
    call disptextz
    ld hl, lookup_name
    call disptextz
    ld a, '.'
    call printchar
    ld a, '.'
    call printchar
    ld a, '.'
    call printchar
    call crlf

    ; Call DNS resolution (with timeout protection)
    ld hl, msgdebug_calling_dns
    call disptextz
    call crlf

    call dns_resolve
    pop hl              ; Restore position for port parsing
    push hl             ; Save it again for check_port

    jr c, .lookup_fail

    ld hl, msgok
    call disptextz
    call crlf

    ; Display resolved IP
    ld hl, msgresolved
    call disptextz
    ld hl, ip_addr
    call disp_ip
    call crlf

    ; IP is now in ip_addr, continue to port parsing
    pop hl              ; Restore buffer position (at ':' or null)
    jr check_port

.lookup_fail:
    pop hl              ; Clean up stack (buffer position was pushed)
    ld hl, msgfail
    call disptextz

    ; Display error code
    push af
    ld hl, msgerror_code
    call disptextz
    pop af
    push af
    call disp_dec
    call crlf
    pop af

    ld a, 1
    ret

; Convert ASCII IP to binary (format: x.x.x.x)
convert_ip:
    ld hl, buf
    call ascii2dec
    ld (ip_addr), a        ; First octet at ip_addr+0
    call ascii2dec
    ld (ip_addr+1), a      ; Second octet at ip_addr+1
    call ascii2dec
    ld (ip_addr+2), a      ; Third octet at ip_addr+2
    call ascii2dec
    ld (ip_addr+3), a      ; Fourth octet at ip_addr+3
    dec hl                 ; Back up to point at final separator (':' or null)

check_port:
    ld a, (hl)
    cp ':'              ; Port specified?
    jr nz, no_port

    ; Debug: port specified
    push hl
    ld hl, msgdebug_port_specified
    call disptextz
    pop hl

    push hl
    pop ix
    call port2dec

    ; Debug: show parsed port value
    push hl
    ld hl, msgdebug_port_value
    call disptextz
    pop hl
    push hl
    call disp_dec16
    call crlf
    pop hl

    jr got_port

no_port:
    ; Debug: using default port
    push hl
    ld hl, msgdebug_port_default
    call disptextz
    call crlf
    pop hl

    ld hl, 23           ; Default to telnet port

got_port:
    ; Debug: storing port value
    push hl
    ld hl, msgdebug_storing_port
    call disptextz
    pop hl
    push hl

    ; Show raw hex value
    push hl
    ld hl, msgdebug_port_hex
    call disptextz
    pop hl
    push hl
    ld a, h
    call disp_hex_byte
    ld a, l
    call disp_hex_byte
    ld a, ' '
    call printchar
    ld a, 61            ; '=' character
    call printchar
    ld a, ' '
    call printchar
    pop hl
    push hl

    call disp_dec16
    call crlf
    pop hl

    ; Store port directly (no byte swapping needed)
    ld (port), hl
    xor a
    ret

; Display byte in hex
disp_hex_byte:
    push af
    push bc
    ld b, a
    rrca
    rrca
    rrca
    rrca
    and 0x0F
    call disp_hex_digit
    ld a, b
    and 0x0F
    call disp_hex_digit
    pop bc
    pop af
    ret

disp_hex_digit:
    cp 10
    jr c, .is_digit
    add a, 'A' - 10
    jp printchar
.is_digit:
    add a, '0'
    jp printchar

;-------------------------------------------------------
; DNS_RESOLVE - Resolve domain name to IP
; Entry: lookup_name = null-terminated domain name
; Exit:  ip_addr = resolved IP (4 bytes)
;        Carry clear if OK, set if error
;-------------------------------------------------------
dns_resolve:
    push hl
    push de
    push bc

    ; Call our DNS resolver
    ld hl, lookup_name  ; HL = hostname
    ld de, ip_addr      ; DE = result buffer
    call RESOLVE_HOSTNAME
    jr c, .dns_error

    or a                ; Clear carry
    xor a               ; A = 0 for success

.dns_exit:
    pop bc
    pop de
    pop hl
    ret

.dns_error:
    ; A already has error code from RESOLVE_HOSTNAME
    push af
    ld hl, msgdebug_resolve_err
    call disptextz
    pop af
    push af
    call disp_dec
    call crlf
    pop af
    scf
    jr .dns_exit

; Get text input
; HL = dest buffer
; BC = out size
get_textinput:
    ld bc, 0

.input_loop:
    call KM_WAIT_CHAR
    cp 27               ; ESC (0x1B)
    jr z, .input_esc
    cp 127              ; DEL (0x7F)
    jr z, .input_del
    cp 13               ; ENTER/CR (0x0D)
    jr z, .input_done
    cp 32
    jr c, .input_loop   ; Ignore control chars

    ; Echo and store character
    push bc
    call printchar
    pop bc

    ld (hl), a
    inc hl
    inc bc
    jr .input_loop

.input_del:
    ld a, b
    or c
    jr z, .input_loop   ; Nothing to delete

    dec hl
    dec bc

    ; Backspace on screen
    ld a, 8
    push bc
    call printchar
    ld a, 32
    call printchar
    ld a, 8
    call printchar
    pop bc
    jr .input_loop

.input_done:
    ld a, 0
    ld (hl), a          ; Null terminate
    call crlf
    ld a, 0
    ret

.input_esc:
    ld bc, 0
    ld a, 0xFC
    ret

; Convert ASCII decimal to binary
; HL = pointer to ASCII string
; Returns: A = binary value
;          HL = pointer PAST separator (ready for next call)
ascii2dec:
    push bc
    ld b, 0

.dec_loop:
    ld a, (hl)
    cp '.'
    jr z, .dec_done
    cp ':'
    jr z, .dec_done
    cp 0
    jr z, .dec_done

    sub '0'
    ld c, a
    ld a, b
    add a, a            ; *2
    add a, a            ; *4
    add a, b            ; *5
    add a, a            ; *10
    add a, c
    ld b, a
    inc hl
    jr .dec_loop

.dec_done:
    inc hl          ; Move past separator for next call
    ld a, b
    pop bc
    ret

; Convert port string to number
; IX = pointer to ':'
; Returns: HL = port number
port2dec:
    push bc
    push ix
    pop hl
    inc hl              ; Skip ':'

    ld bc, 0

.port_loop:
    ld a, (hl)
    inc hl
    cp 0
    jr z, .port_done

    sub '0'
    ld d, a

    ; BC = BC * 10 + D
    push hl
    ld h, b
    ld l, c
    add hl, hl          ; *2
    add hl, hl          ; *4
    add hl, bc          ; *5
    add hl, hl          ; *10
    ld b, 0
    ld c, d
    add hl, bc
    ld b, h
    ld c, l
    pop hl

    jr .port_loop

.port_done:
    ld h, b
    ld l, c
    pop bc
    ret

; Display IP address
; HL = pointer to IP (4 bytes)
disp_ip:
    push hl
    push bc

    ld b, 4

.ip_loop:
    ld a, (hl)
    push hl
    push bc
    call disp_dec       ; Display decimal
    pop bc
    pop hl

    inc hl
    dec b
    jr z, .ip_done

    ld a, '.'
    push hl
    push bc
    call printchar
    pop bc
    pop hl

    jr .ip_loop

.ip_done:
    pop bc
    pop hl
    ret

; Display port number
; HL = port number (16-bit)
disp_port:
    push af
    push bc
    push de
    push hl

    ; Display as 16-bit decimal
    call disp_dec16

    pop hl
    pop de
    pop bc
    pop af
    ret

; Display 16-bit decimal number (HL = value)
; Uses M4EWENTERM's algorithm with negative divisors
disp_dec16:
    push af
    push bc
    push hl

    ld bc, -10000
    call n16_1
    cp '0'
    jr nz, not16_lead0
    ld bc, -1000
    call n16_1
    cp '0'
    jr nz, not16_lead1
    ld bc, -100
    call n16_1
    cp '0'
    jr nz, not16_lead2
    ld bc, -10
    call n16_1
    cp '0'
    jr nz, not16_lead3
    jr not16_lead4

not16_lead0:
    call printchar
    ld bc, -1000
    call n16_1
not16_lead1:
    call printchar
    ld bc, -100
    call n16_1
not16_lead2:
    call printchar
    ld c, -10
    call n16_1
not16_lead3:
    call printchar
not16_lead4:
    ld c, b
    call n16_1
    call printchar

    pop hl
    pop bc
    pop af
    ret

; Divide HL by BC (negative), return ASCII digit in A
n16_1:
    ld a, '0' - 1
n16_2:
    inc a
    add hl, bc
    jr c, n16_2
    sbc hl, bc
    ret

; Display decimal number
; A = number
disp_dec:
    push af
    push bc
    push de
    push hl

    ld e, a
    ld d, 0
    ld hl, 0

    ; Hundreds
    ld bc, 100
    ld a, e

.div_100:
    cp c
    jr c, .done_100
    sub c
    inc l
    jr .div_100

.done_100:
    ld e, a
    ld a, l
    or a
    jr z, .skip_100
    add a, '0'
    call printchar

.skip_100:
    ; Tens
    ld a, e
    ld l, 0

.div_10:
    cp 10
    jr c, .done_10
    sub 10
    inc l
    jr .div_10

.done_10:
    push af
    ld a, l
    or a
    jr nz, .show_10
    ld a, (hl)      ; Check if we printed hundreds
    cp 0
    jr z, .skip_10

.show_10:
    ld a, l
    add a, '0'
    call printchar

.skip_10:
    ; Ones
    pop af
    add a, '0'
    call printchar

    pop hl
    pop de
    pop bc
    pop af
    ret

crlf:
    push af
    ld a, 13
    call printchar
    ld a, 10
    call printchar
    pop af
    ret

; Buffers
buf:            ds 128
lookup_name:    ds 256

msgresolve:     db "Resolving: ",0
msgok:          db " OK",0
msgfail:        db " FAILED!",0
msgresolved:    db "Resolved to: ",0
msgerror_code:  db "Error code: ",0
msgdebug_input: db "[DEBUG] Input: ",0
msgdebug_dns:   db "[DEBUG] Domain lookup mode",0
msgdebug_parseip: db "[DEBUG] IP parsing mode",0
msgdebug_calling_dns: db "[DEBUG] Calling DNS resolver...",0
msgdebug_resolve_err: db "[DEBUG] DNS resolver returned error: ",0
msgdebug_port_specified: db "[DEBUG] Port specified in input",10,13,0
msgdebug_port_default: db "[DEBUG] Using default port 23",0
msgdebug_port_value: db "[DEBUG] Parsed port value: ",0
msgdebug_storing_port: db "[DEBUG] Storing port: ",0
msgdebug_port_hex: db "(hex: 0x",0
