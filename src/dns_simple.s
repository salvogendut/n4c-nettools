; Simple DNS resolver for Net4CPC
; Based on KCNet documentation
; Implements only basic A record lookup (hostname -> IP)

;=======================================================
; DNS Protocol Constants
;=======================================================
DNS_PORT        equ 53
DNS_TIMEOUT     equ 3000        ; 3 seconds in milliseconds

; DNS Message Header Structure (12 bytes)
; +0:  Transaction ID (2 bytes)
; +2:  Flags (2 bytes)
; +4:  Questions (2 bytes)
; +6:  Answer RRs (2 bytes)
; +8:  Authority RRs (2 bytes)
; +10: Additional RRs (2 bytes)

; DNS Flags
DNS_QR_QUERY    equ 0x00        ; This is a query
DNS_QR_RESPONSE equ 0x80        ; This is a response
DNS_RD          equ 0x01        ; Recursion desired

; DNS Record Types
DNS_TYPE_A      equ 1           ; IPv4 address
DNS_CLASS_IN    equ 1           ; Internet class

;=======================================================
; RESOLVE_HOSTNAME - Simple DNS A record lookup
; Entry: HL = pointer to hostname string (null-terminated)
;        DE = pointer to buffer for result (4 bytes for IP)
; Exit:  Carry clear if OK, set if error
;        A = error code if carry set
;=======================================================
RESOLVE_HOSTNAME:
    ld a, 1
    ld (dns_debug_marker), a

    push hl
    push de
    push bc

    ld a, 2
    ld (dns_debug_marker), a

    ; Pop to get hostname pointer
    pop bc                      ; BC = saved BC
    pop de                      ; DE = result buffer
    pop hl                      ; HL = hostname pointer

    ld a, 3
    ld (dns_debug_marker), a

    ; Copy hostname to dns_hostname_buf
    push de                     ; Save result buffer
    push bc                     ; Save BC
    ld de, dns_hostname_buf
    call dns_strcpy

    ld a, 4
    ld (dns_debug_marker), a

    ; Restore and rebuild stack
    pop bc
    pop de

    ld a, 5
    ld (dns_debug_marker), a

    ; Save result buffer pointer (DE will be destroyed by SOCKET call)
    ld (dns_result_ptr), de

    ; Open UDP socket
    ld a, 0xFF                  ; Auto-allocate
    ld d, SK_DGRAM              ; UDP mode
    ld e, 0                     ; No flags
    call SOCKET
    jp c, .error_socket

    ld a, 6
    ld (dns_debug_marker), a

    ld (dns_socket), a          ; Save socket number

    ld a, 7
    ld (dns_debug_marker), a

    ; Build DNS query
    call dns_build_query
    jp c, .error_build

    ld a, 8
    ld (dns_debug_marker), a

    ; Send query
    ld a, (dns_socket)
    ld hl, dns_query_buf
    ld bc, (dns_query_len)
    ld de, dns_peer_data
    call SENDTO
    jp c, .error_send

    ld a, 9
    ld (dns_debug_marker), a

    ; Save send time
    call N_TIME
    ld (dns_send_time), hl

    ld a, 10
    ld (dns_debug_marker), a

    ; Wait for response
    ld bc, 0                    ; Loop counter
.wait_loop:
    inc bc

    ; Check timeout
    call N_TIME
    ld de, (dns_send_time)
    or a
    sbc hl, de                  ; HL = elapsed
    ld de, DNS_TIMEOUT
    or a
    sbc hl, de
    jp nc, .timeout             ; Timed out

    ; Check for data
    ld a, (dns_socket)
    ld e, SL_RECV
    call SELECT
    jp c, .wait_loop            ; No data yet

    ; Data available!
    ld a, 11
    ld (dns_debug_marker), a

    ; Simple UDP receive - read directly from W5100S RX buffer
    ; Get RX_RD pointer
    ld hl, 0x0528               ; S1_RX_RD0
    call W5100_READ_REG
    ld d, a
    ld hl, 0x0529
    call W5100_READ_REG
    ld e, a                     ; DE = RX_RD

    ; Skip 8-byte UDP header (4 IP + 2 port + 2 size)
    ld hl, 8
    add hl, de                  ; HL = RX_RD + 8
    ld d, h
    ld e, l

    ; Mask to buffer size (0x07FF for 2KB) and add base
    ld a, e
    and 0xFF                    ; LSB: keep all bits
    ld l, a
    ld a, d
    and 0x07                    ; MSB: mask to 2KB
    ld h, a
    ld de, 0x6800               ; S1_RX_BASE
    add hl, de                  ; HL = physical address in W5100S

    ; Read 64 bytes of DNS response
    ex de, hl                   ; DE = W5100S address
    ld hl, dns_response_buf     ; HL = our buffer
    ld bc, 64                   ; Read 64 bytes
    call W5100_READ_BUF

    ; Update RX_RD pointer (add 8 + 64 = 72)
    ld hl, 0x0528
    call W5100_READ_REG
    ld h, a
    ld hl, 0x0529
    call W5100_READ_REG
    ld l, a
    ld de, 72
    add hl, de
    ld d, h
    ld e, l
    ld hl, 0x0528
    ld a, d
    call W5100_WRITE_REG
    inc hl
    ld a, e
    call W5100_WRITE_REG

    ; Issue RECV command
    ld hl, 0x0501               ; S1_CR
    ld a, 0x40                  ; SCMD_RECV
    call W5100_WRITE_REG

    ld a, 12
    ld (dns_debug_marker), a

    ; Parse DNS response to extract IP
    ; Restore the result buffer pointer that was passed in
    ld de, (dns_result_ptr)
    call dns_parse_response
    jp c, .error_parse

    ld a, 14
    ld (dns_debug_marker), a

    ; Close socket
    ld a, (dns_socket)
    call CLOSE

    ld a, 15
    ld (dns_debug_marker), a

    ; Return success (carry clear)
    or a                        ; Clear carry
    ret

.error_parse:
    ; Save error code
    push af
    ld a, (dns_socket)
    call CLOSE
    pop af
    scf
    ret

.timeout:
    ld a, (dns_socket)
    call CLOSE
    scf
    ld a, 20                    ; Error 20 = timeout
    ret

.error_build:
    ld a, (dns_socket)
    call CLOSE
    scf
    ld a, 18                    ; Error 18 = build failed
    ret

.error_send:
    ld a, (dns_socket)
    call CLOSE
    scf
    ld a, 19                    ; Error 19 = send failed
    ret

.error_socket:
    scf
    ld a, 16                    ; Error 16 = socket failed
    ret

;=======================================================
; DNS_BUILD_QUERY - Build DNS query message
; Entry: dns_hostname_buf = hostname to resolve
; Exit:  dns_query_buf = query message
;        dns_query_len = message length
;        Carry set if error
;=======================================================
dns_build_query:
    push hl
    push de
    push bc

    ; Build peer data (DNS server IP + port)
    ld hl, dns_peer_data
    ld a, N_DNSIP
    call N_RIPA                 ; Read DNS IP from W5100S
    ld (hl), 0                  ; Port MSB
    inc hl
    ld (hl), DNS_PORT           ; Port LSB
    inc hl

    ; Start building query message
    ld hl, dns_query_buf

    ; Transaction ID (use dynamic port number)
    call N_DPRT                 ; Returns HL = port in network order
    ex de, hl                   ; DE = port
    ld hl, dns_query_buf
    ld (hl), d
    inc hl
    ld (hl), e
    inc hl
    ex de, hl                   ; DE back to buffer pointer

    ; Flags: standard query with recursion desired
    ld (de), a                  ; Flags byte 0: QR=0, Opcode=0, AA=0, TC=0, RD=1
    ld a, DNS_RD
    ld (de), a
    inc de
    xor a
    ld (de), a                  ; Flags byte 1: all zeros
    inc de

    ; Question count = 1
    ld (de), a                  ; MSB = 0
    inc de
    ld a, 1
    ld (de), a                  ; LSB = 1
    inc de

    ; Answer count = 0
    xor a
    ld (de), a
    inc de
    ld (de), a
    inc de

    ; Authority count = 0
    ld (de), a
    inc de
    ld (de), a
    inc de

    ; Additional count = 0
    ld (de), a
    inc de
    ld (de), a
    inc de

    ; Now build the question section
    ; Convert hostname to DNS name format (label length + label)
    ld hl, dns_hostname_buf
    call dns_encode_name        ; DE points after encoded name

    ; Add QTYPE (A = 1)
    xor a
    ld (de), a                  ; MSB = 0
    inc de
    ld a, DNS_TYPE_A
    ld (de), a                  ; LSB = 1
    inc de

    ; Add QCLASS (IN = 1)
    xor a
    ld (de), a                  ; MSB = 0
    inc de
    ld a, DNS_CLASS_IN
    ld (de), a                  ; LSB = 1
    inc de

    ; Calculate total length
    ld hl, dns_query_buf
    ex de, hl
    or a
    sbc hl, de
    ld (dns_query_len), hl

    pop bc
    pop de
    pop hl
    or a                        ; Clear carry
    ret

;=======================================================
; DNS_ENCODE_NAME - Encode hostname in DNS format
; Entry: HL = hostname (e.g., "google.com")
;        DE = output buffer (after header)
; Exit:  DE = pointer after encoded name
;=======================================================
dns_encode_name:
    push hl
    push bc

.next_label:
    ; Count label length
    push de                     ; Save label length position
    inc de                      ; Skip length byte for now
    ld b, 0                     ; Label character counter

.count_loop:
    ld a, (hl)
    or a
    jr z, .end_label            ; Null terminator
    cp '.'
    jr z, .end_label            ; Dot separator
    inc hl
    ld (de), a                  ; Copy character
    inc de
    inc b
    ld a, b
    cp 63                       ; Max label length
    jr z, .end_label
    jr .count_loop

.end_label:
    ; Write label length
    ld a, b                     ; Save counter to A FIRST (before pop overwrites B!)
    pop bc                      ; BC = label length position
    push hl
    ld h, b
    ld l, c
    ld (hl), a                  ; Write length (from A, not B!)
    pop hl

    ; Check if done
    ld a, (hl)
    or a
    jr z, .done                 ; Null terminator - done
    inc hl                      ; Skip dot
    jr .next_label

.done:
    ; Write terminating zero length
    xor a
    ld (de), a
    inc de

    pop bc
    pop hl
    ret

;=======================================================
; DNS_PARSE_RESPONSE - Parse DNS response
; Entry: dns_response_buf = response message
;        DE = result buffer (4 bytes for IP)
; Exit:  Carry clear if OK, set if error
;=======================================================
dns_parse_response:
    push hl
    push bc

    ld hl, dns_response_buf

    ; Check response bit (byte 2, bit 7)
    inc hl
    inc hl
    ld a, (hl)
    and DNS_QR_RESPONSE
    jr z, .error_not_response   ; Not a response

    ; Check error code (byte 3, low 4 bits)
    inc hl
    ld a, (hl)
    and 0x0F
    jr nz, .error_server        ; Server returned error

    ; Skip to answers (skip rest of header + question)
    ; Header is 12 bytes total, we're at byte 3
    ld bc, 8
    add hl, bc                  ; HL now at byte 11 (last header byte)

    ; Skip question section (we know it's 1 question)
    ; Need to skip: QNAME + QTYPE + QCLASS
    inc hl                      ; HL now at byte 12 (start of question)

    ; Skip QNAME (find the 0 length byte)
.skip_qname:
    ld a, (hl)
    inc hl
    or a
    jr z, .qname_done
    ; Check for compression pointer
    and 0xC0
    cp 0xC0
    jr z, .skip_pointer
    ; Regular label - skip it
    dec hl
    ld a, (hl)
    inc hl
    ld b, a
.skip_label:
    inc hl
    djnz .skip_label
    jr .skip_qname

.skip_pointer:
    inc hl                      ; Skip pointer byte
    jr .qname_done

.qname_done:
    ; Skip QTYPE and QCLASS (4 bytes)
    ld bc, 4
    add hl, bc

    ; Now at answer section
    ; Skip answer NAME (compression pointer most likely)
    ld a, (hl)
    and 0xC0
    cp 0xC0
    jr nz, .error_name_not_ptr  ; Should be pointer
    inc hl
    inc hl                      ; Skip 2-byte pointer

    ; Check TYPE (should be A = 1)
    ld a, (hl)
    inc hl
    or a
    jr nz, .error_type_msb
    ld a, (hl)
    inc hl
    cp DNS_TYPE_A
    jr nz, .error_type_lsb

    ; Skip CLASS (2 bytes) and TTL (4 bytes)
    ld bc, 6
    add hl, bc

    ; Check RDLENGTH (should be 4 for IPv4)
    ld a, (hl)
    inc hl
    or a
    jr nz, .error_rdlen_msb
    ld a, (hl)
    inc hl
    cp 4
    jr nz, .error_rdlen_lsb

    ; Copy 4-byte IP address to result buffer
    ld bc, 4
    ldir

    pop bc
    pop hl
    and a                       ; Clear carry (AND clears carry flag)
    ret

.error_not_response:
    pop bc
    pop hl
    scf
    ld a, 21                    ; Error: QR bit not set (not a response)
    ret

.error_server:
    pop bc
    pop hl
    scf
    ld a, 22                    ; Error: DNS server returned error code
    ret

.error_name_not_ptr:
    pop bc
    pop hl
    scf
    ld a, 23                    ; Error: Answer name not a pointer
    ret

.error_type_msb:
    pop bc
    pop hl
    scf
    ld a, 24                    ; Error: TYPE MSB not 0
    ret

.error_type_lsb:
    pop bc
    pop hl
    scf
    ld a, 25                    ; Error: TYPE not A record
    ret

.error_rdlen_msb:
    pop bc
    pop hl
    scf
    ld a, 26                    ; Error: RDLENGTH MSB not 0
    ret

.error_rdlen_lsb:
    pop bc
    pop hl
    scf
    ld a, 27                    ; Error: RDLENGTH not 4
    ret

;=======================================================
; DNS_STRCPY - Copy null-terminated string
; HL = source, DE = destination
;=======================================================
dns_strcpy:
    ld a, (hl)
    ld (de), a
    or a
    ret z
    inc hl
    inc de
    jr dns_strcpy

;=======================================================
; DNS Data Buffers
;=======================================================
dns_socket:         db 0
dns_send_time:      dw 0
dns_timeout_time:   dw 0
dns_query_len:      dw 0
dns_result_ptr:     dw 0
dns_debug_loops:    dw 0
dns_debug_time_start: dw 0
dns_debug_time_end:   dw 0
dns_debug_time_now:   dw 0
dns_debug_response: ds 8        ; First 8 bytes of response
dns_debug_rx_rsr:   dw 0        ; RX received size
dns_debug_rx_rd:    dw 0        ; RX read pointer
dns_debug_marker:   db 0        ; Debug checkpoint marker
dns_debug_socket_status: db 0   ; Socket status (S1_SR)
dns_debug_src_port: dw 0        ; Source port from S1_PORT
dns_debug_dest_ip:  ds 4        ; Destination IP from S1_DIPR
dns_debug_dest_port: dw 0       ; Destination port from S1_DPORT
dns_peer_data:      ds 8        ; 4 bytes IP + 2 bytes port + 2 bytes size (RECVFR needs 8!)
dns_hostname_buf:   ds 256
dns_query_buf:      ds 512
dns_response_buf:   ds 512
result_ip_temp:     ds 4        ; Temp buffer for testing DNS parsing
