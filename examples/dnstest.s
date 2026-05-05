; Simple DNS test program for Net4CPC
; Tests GHBNAM function standalone

    org 0x7000

; Firmware routines
TXT_OUTPUT equ 0xBB5A
KM_WAIT_CHAR equ 0xBB06

start:
    ; Initialize W5100S mode register (required!)
    ld bc, 0xFD20
    ld a, 3                     ; Auto-increment + indirect bus mode
    out (c), a

    ; Print banner
    ld hl, msg_banner
    call print_string

    ; Setup test hostname
    ld hl, test_hostname
    ld de, domain_buffer
    call strcpy

    ; Print what we're resolving
    ld hl, msg_resolving
    call print_string
    ld hl, domain_buffer
    call print_string
    call print_crlf

    ; DEBUG: Read and print DNS server IP
    ld hl, msg_dns_ip
    call print_string
    ld hl, dns_debug_ip
    ld a, 0                     ; N_DNSIP = 0
    call N_RIPA
    ld hl, dns_debug_ip
    ld b, 4
.print_dns_loop:
    ld a, (hl)
    push hl
    push bc
    call print_decimal
    pop bc
    pop hl
    inc hl
    dec b
    jr z, .dns_done
    ld a, '.'
    call print_char
    jr .print_dns_loop
.dns_done:
    call print_crlf

    ; DEBUG: Print before calling resolver
    ld hl, msg_calling
    call print_string

    ; DEBUG: Test - can we call a simple function?
    call test_func

    ld a, 'O'
    call print_char
    ld a, 'K'
    call print_char
    call print_crlf

    ; Now try calling RESOLVE_HOSTNAME
    ld hl, msg_test_skip
    call print_string

    ld hl, domain_buffer
    ld de, result_ip
    call RESOLVE_HOSTNAME

    ; Save error code BEFORE printing anything
    push af

    ld a, '!'
    call print_char

    pop af
    jp c, dns_failed

    ; Call DNS resolver
    ld hl, domain_buffer        ; HL = hostname
    ld de, result_ip            ; DE = result buffer

    ; Set a timeout to check marker if it hangs
    call RESOLVE_HOSTNAME

    ; DEBUG: Print after calling resolver
    ld hl, msg_returned
    call print_string

    ; Show marker value
    ld hl, msg_marker
    call print_string
    ld a, (dns_debug_marker)
    call print_decimal
    call print_crlf

    jp c, dns_failed

    ; SUCCESS! Print the resolved IP
    ld hl, msg_success
    call print_string

    ; IP is in result_ip_temp
    ld hl, result_ip_temp
    ld b, 4
.print_ip_success:
    ld a, (hl)
    push hl
    push bc
    call print_decimal
    pop bc
    pop hl
    inc hl
    dec b
    jr z, .ip_done_success
    ld a, '.'
    call print_char
    jr .print_ip_success

.ip_done_success:
    call print_crlf
    ld hl, msg_done
    call print_string
    ret

msg_bug: db "BUG: No error but failed?",13,10,0

    ; Success - print resolved IP
    ld hl, msg_success
    call print_string

    ; IP is now in result_ip (4 bytes)
    ld hl, result_ip
    ld b, 4
print_ip_loop:
    ld a, (hl)
    push hl
    push bc
    call print_decimal
    pop bc
    pop hl
    inc hl
    dec b
    jr z, print_ip_done
    ld a, '.'
    call print_char
    jr print_ip_loop

print_ip_done:
    call print_crlf
    ld hl, msg_done
    call print_string
    ret

dns_failed:
    ; Save error code FIRST before any function calls
    push af

    ; Print marker first
    ld hl, msg_marker
    call print_string
    ld a, (dns_debug_marker)
    call print_decimal
    call print_crlf

    ; Print error
    ld hl, msg_failed
    call print_string

    ; Print error code
    ld hl, msg_error
    call print_string
    pop af

    ; Check if it's error 19 (SENDTO failed)
    cp 19
    jr nz, .not_sendto_err
    ld hl, msg_sendto_fail
    call print_string
    jp .done

.not_sendto_err:
    push af
    call print_decimal
    call print_crlf
    pop af

    ; If error 23 (parse error), show first 32 bytes of response
    cp 23
    jp nz, .not_err23

    ld hl, msg_recv_bytes
    call print_string
    ld hl, dns_response_buf
    ld b, 32
.print_resp_loop:
    ld a, (hl)
    push hl
    push bc
    call print_hex8
    ld a, ' '
    call print_char
    pop bc
    pop hl
    inc hl
    djnz .print_resp_loop
    call print_crlf
    jp .done

.not_err23:
    ; If error 11 (no data), show debug info
    cp 11
    jp nz, .not_err11

    ld hl, msg_socket_status
    call print_string
    ld a, (dns_debug_socket_status)
    call print_hex8
    call print_crlf

    ld hl, msg_rx_rsr
    call print_string
    ld hl, (dns_debug_rx_rsr)
    call print_hex16
    call print_crlf

    ; Print first 32 bytes of DNS query
    ld hl, msg_query
    call print_string
    ld hl, dns_query_buf
    ld b, 32
.print_query_loop:
    ld a, (hl)
    push hl
    push bc
    call print_hex8
    ld a, ' '
    call print_char
    pop bc
    pop hl
    inc hl
    djnz .print_query_loop
    call print_crlf

    ; Print query length
    ld hl, msg_query_len
    call print_string
    ld hl, (dns_query_len)
    call print_hex16
    call print_crlf

    ; Print peer data (DNS server IP + port)
    ld hl, msg_peer
    call print_string
    ld hl, dns_peer_data
    ld b, 6
.print_peer_loop:
    ld a, (hl)
    push hl
    push bc
    call print_hex8
    ld a, ' '
    call print_char
    pop bc
    pop hl
    inc hl
    djnz .print_peer_loop
    call print_crlf

    ; Print W5100S register values
    ld hl, msg_src_port
    call print_string
    ld hl, (dns_debug_src_port)
    call print_hex16
    call print_crlf

    ld hl, msg_dest_ip
    call print_string
    ld hl, dns_debug_dest_ip
    ld b, 4
.print_dest_ip_loop:
    ld a, (hl)
    push hl
    push bc
    call print_hex8
    ld a, ' '
    call print_char
    pop bc
    pop hl
    inc hl
    djnz .print_dest_ip_loop
    call print_crlf

    ld hl, msg_dest_port
    call print_string
    ld hl, (dns_debug_dest_port)
    call print_hex16
    call print_crlf

    jp .done

.not_err11:
    ; If error 21 (bad response), show received bytes
    cp 21
    jr nz, .not_err21

    ld hl, msg_rx_rsr
    call print_string
    ld hl, (dns_debug_rx_rsr)
    call print_hex16
    call print_crlf

    ld hl, msg_rx_rd
    call print_string
    ld hl, (dns_debug_rx_rd)
    call print_hex16
    call print_crlf

    ld hl, msg_recv_bytes
    call print_string
    ld hl, dns_debug_response
    ld b, 8
.print_recv_loop:
    ld a, (hl)
    push hl
    push bc
    call print_hex8
    ld a, ' '
    call print_char
    pop bc
    pop hl
    inc hl
    djnz .print_recv_loop
    call print_crlf
    jp .done

.not_err21:
    ; If error 20 (timeout), show debug info
    cp 20
    jr nz, .done

    ld hl, msg_loops
    call print_string
    ld hl, (dns_debug_loops)
    ld a, l
    call print_decimal
    ld a, h
    call print_decimal
    call print_crlf

    ; Show time values
    ld hl, msg_time_start
    call print_string
    ld hl, (dns_debug_time_start)
    call print_hex16
    call print_crlf

    ld hl, msg_time_end
    call print_string
    ld hl, (dns_debug_time_end)
    call print_hex16
    call print_crlf

    ld hl, msg_time_now
    call print_string
    ld hl, (dns_debug_time_now)
    call print_hex16
    call print_crlf

.done:
    ld hl, msg_done
    call print_string
    ret

; Helper: Copy string
; HL = source, DE = dest
strcpy:
    ld a, (hl)
    ld (de), a
    or a
    ret z
    inc hl
    inc de
    jr strcpy

; Helper: Print string (zero-terminated)
print_string:
    ld a, (hl)
    or a
    ret z
    call print_char
    inc hl
    jr print_string

print_char:
    push hl
    push de
    push bc
    call TXT_OUTPUT
    pop bc
    pop de
    pop hl
    ret

print_crlf:
    ld a, 13
    call print_char
    ld a, 10
    call print_char
    ret

; Helper: Print 16-bit hex (HL = number)
print_hex16:
    push af
    ld a, h
    call print_hex8
    ld a, l
    call print_hex8
    pop af
    ret

; Helper: Print 8-bit hex (A = number)
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
    call print_char
    ret

; Helper: Print decimal number (A = number)
print_decimal:
    push af
    push bc
    push de
    push hl

    ld e, a
    ld d, 0             ; D will track if we printed anything

    ; Hundreds
    ld b, 0
    ld a, e
.div_100:
    cp 100
    jr c, .done_100
    sub 100
    inc b
    jr .div_100

.done_100:
    ld e, a             ; Save remainder
    ld a, b
    or a
    jr z, .skip_100
    add a, '0'
    call print_char
    ld d, 1             ; Mark that we printed something

.skip_100:
    ; Tens
    ld b, 0
    ld a, e
.div_10:
    cp 10
    jr c, .done_10
    sub 10
    inc b
    jr .div_10

.done_10:
    ld e, a             ; Save remainder (ones)
    ld a, b
    or a
    jr nz, .show_10
    ; Only skip tens if we didn't print hundreds
    ld a, d
    or a
    jr z, .skip_10

.show_10:
    ld a, b
    add a, '0'
    call print_char

.skip_10:
    ; Ones - always print
    ld a, e
    add a, '0'
    call print_char

    pop hl
    pop de
    pop bc
    pop af
    ret

; Messages
msg_banner:     db "DNS Test Program",13,10
                db "================",13,10,0
msg_resolving:  db "Resolving: ",0
msg_dns_ip:     db "DNS Server: ",0
msg_calling:    db "Calling...",13,10,0
msg_test_skip:  db "Test: skipping call",13,10,0
msg_returned:   db "Returned!",13,10,0
msg_marker:     db "Marker: ",0
msg_success:    db "Success! IP: ",0
msg_failed:     db "FAILED!",13,10,0
msg_error:      db "Error code: ",0
msg_sendto_fail: db "19 (SENDTO timeout)",13,10,0
msg_socket_status: db "Socket status: ",0
msg_rx_rsr:     db "RX_RSR: ",0
msg_rx_rd:      db "RX_RD: ",0
msg_recv_bytes: db "First 8 bytes: ",0
msg_loops:      db "Wait loops: ",0
msg_time_start: db "Start time: ",0
msg_time_end:   db "Timeout at: ",0
msg_time_now:   db "Actual time: ",0
msg_query:      db "Query (32B): ",0
msg_query_len:  db "Query len: ",0
msg_peer:       db "Peer data: ",0
msg_src_port:   db "S1_PORT: ",0
msg_dest_ip:    db "S1_DIPR: ",0
msg_dest_port:  db "S1_DPORT: ",0
msg_done:       db 13,10,"Press any key...",0

; Test hostname (change this to test different hosts)
test_hostname:  db "google.com",0

; Buffers
domain_buffer:  ds 256
result_ip:      ds 4
dns_debug_ip:   ds 4

; Test function to verify CALL works
test_func:
    ld a, 'T'
    call print_char
    ret

; Include the W5100 socket layer and simple DNS client
    include "../src/w5100.s"
    include "../src/dns_simple.s"

SAVE 'DNS.BIN',#7000,$-#7000,AMSDOS
