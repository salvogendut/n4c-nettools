; =============================================================================
; NTP.S  -  NTP/SNTP time client for Amstrad CPC / AMSDOS
;           Uses n4c-nettools (salvogendut/n4c-nettools) library
;
; Implements RFC 4330 (SNTPv4) - sends a minimal 48-byte NTP request,
; receives the 48-byte reply, extracts the Transmit Timestamp (seconds
; since 1900-01-01), converts to human-readable date/time and displays it.
;
; Build (from drafts/ directory, after copying library files):
;   cp ../src/w5100.s ../src/dns_simple.s ../src/n4c-netinit-kv.s .
;   rasm ntp.s
;
; BASIC loader:
;   10 MEMORY &3DFF
;   20 LOAD "NTP.BIN",&4000
;   30 CALL &4000
; =============================================================================

        org     0x4000

TXT_OUTPUT      equ     0xBB5A
KM_WAIT_CHAR    equ     0xBB06
KL_TIME_PLEASE  equ     0xBD19      ; firmware: HL = elapsed 1/300s ticks

; SK_DGRAM and SL_RECV are defined in w5100.s (included below)

NTP_PORT        equ     123
NTP_PKT_SIZE    equ     48

; =============================================================================
; MAIN ENTRY POINT
; =============================================================================
NTP_START:
        push    iy

        ld      hl, msg_banner
        call    PRINT_STR

        ld      hl, msg_init
        call    PRINT_STR
        call    N4C_INIT
        jr      nc, init_ok
        ld      hl, msg_init_err
        call    PRINT_STR
        jp      ntp_exit

init_ok:
        ld      hl, msg_ok
        call    PRINT_STR

        ld      hl, msg_resolving
        call    PRINT_STR
        ld      hl, cfg_ntp_host
        call    PRINT_STR
        call    PRINT_CRLF

        ld      hl, cfg_ntp_host
        ld      de, cfg_ntp_ip
        call    RESOLVE_HOSTNAME
        jr      nc, dns_ok
        push    af
        ld      hl, msg_dns_err
        call    PRINT_STR
        pop     af
        call    PRINT_BYTE_DEC2
        call    PRINT_CRLF
        jp      ntp_exit

dns_ok:
        ld      hl, msg_server_ip
        call    PRINT_STR
        ld      hl, cfg_ntp_ip
        call    NTP_PRINT_IP
        call    PRINT_CRLF

        ; Open UDP socket
        ld      a, 0xFF
        ld      d, SK_DGRAM
        ld      e, 0
        call    SOCKET
        jr      nc, sock_ok
        ld      hl, msg_sock_err
        call    PRINT_STR
        jp      ntp_exit

sock_ok:
        ld      (my_socket), a

        ; Build 48-byte SNTP request: byte 0 = LI=0, VN=4, Mode=3 = 0x23
        ld      hl, ntp_packet
        ld      bc, NTP_PKT_SIZE
        call    ZERO_MEM
        ld      a, 0x23
        ld      (ntp_packet), a

        ; Build peer_data: 4 bytes IP + port MSB + port LSB + 2 bytes size
        ld      hl, cfg_ntp_ip
        ld      de, peer_data
        ld      bc, 4
        ldir
        ld      a, NTP_PORT >> 8
        ld      (de), a
        inc     de
        ld      a, NTP_PORT & 0xFF
        ld      (de), a
        inc     de
        ld      a, 0
        ld      (de), a
        inc     de
        ld      a, NTP_PKT_SIZE
        ld      (de), a

        ld      hl, msg_sending
        call    PRINT_STR

        ld      a, (my_socket)
        ld      hl, ntp_packet
        ld      bc, NTP_PKT_SIZE
        ld      de, peer_data
        call    SENDTO
        jr      nc, send_ok
        ld      hl, msg_send_err
        call    PRINT_STR
        jp      ntp_close

send_ok:
        ld      hl, msg_waiting
        call    PRINT_STR

        ; Wait up to 3 seconds for reply.
        ; Use KL_TIME_PLEASE (&BD19): returns HL = 1/300s ticks since power-on.
        ; ei first: CAS routines may have left interrupts disabled.
        ei
        call    KL_TIME_PLEASE
        ld      (timeout_start), hl

wait_loop:
        call    KL_TIME_PLEASE
        ld      de, (timeout_start)
        or      a
        sbc     hl, de
        ld      de, 900             ; 900 × 1/300s = 3 seconds
        or      a
        sbc     hl, de
        jr      nc, ntp_timeout

        ld      a, (my_socket)
        ld      e, SL_RECV
        call    SELECT
        jr      c, wait_loop

        ; Receive 48-byte NTP reply from socket 1 UDP buffer
        ; W5100S UDP RX: 4-byte IP + 2-byte port + 2-byte size + payload
        ld      hl, S1_RX_RD0
        call    W5100_READ_REG
        ld      d, a
        ld      hl, S1_RX_RD0 + 1
        call    W5100_READ_REG
        ld      e, a            ; DE = RX read pointer

        ; Skip 8-byte UDP header
        ld      hl, 8
        add     hl, de
        ld      d, h
        ld      e, l

        ; Map to physical address
        ld      a, e
        and     S1_RX_MASK & 0xFF
        ld      l, a
        ld      a, d
        and     S1_RX_MASK >> 8
        ld      h, a
        ld      de, S1_RX_BASE
        add     hl, de

        ex      de, hl
        ld      hl, ntp_reply
        ld      bc, NTP_PKT_SIZE
        call    W5100_READ_BUF

        ; Advance RX_RD by 8 + 48 = 56
        ld      hl, S1_RX_RD0
        call    W5100_READ_REG
        ld      d, a
        ld      hl, S1_RX_RD0 + 1
        call    W5100_READ_REG
        ld      e, a
        ld      hl, NTP_PKT_SIZE + 8
        add     hl, de
        ld      d, h
        ld      e, l
        ld      hl, S1_RX_RD0
        ld      a, d
        call    W5100_WRITE_REG
        inc     hl
        ld      a, e
        call    W5100_WRITE_REG

        ld      hl, S1_CR
        ld      a, SCMD_RECV
        call    W5100_WRITE_REG
        jr      recv_ok

ntp_timeout:
        ld      hl, msg_timeout
        call    PRINT_STR
        ; Diagnostics: show socket state, interrupt flags, RX size
        ld      hl, msg_dbg_sr
        call    PRINT_STR
        ld      hl, S1_SR
        call    W5100_READ_REG
        call    PRINT_BYTE_DEC2
        ld      hl, msg_dbg_ir
        call    PRINT_STR
        ld      hl, S1_IR
        call    W5100_READ_REG
        call    PRINT_BYTE_DEC2
        ld      hl, msg_dbg_rsr
        call    PRINT_STR
        ld      hl, S1_RX_RSR0
        call    W5100_READ_REG
        call    PRINT_BYTE_DEC2
        ld      hl, S1_RX_RSR0 + 1
        call    W5100_READ_REG
        call    PRINT_BYTE_DEC2
        call    PRINT_CRLF
        jp      ntp_close

recv_ok:
        ; Verify NTP reply mode (bits 0-2 = 4 or 5)
        ld      a, (ntp_reply)
        and     0x07
        cp      4
        jr      z, mode_ok
        cp      5
        jr      z, mode_ok
        ld      hl, msg_bad_reply
        call    PRINT_STR
        jp      ntp_close

mode_ok:
        ; Stratum 0 = Kiss-o'-Death
        ld      a, (ntp_reply + 1)
        or      a
        jr      nz, stratum_ok
        ld      hl, msg_kod
        call    PRINT_STR
        jp      ntp_close

stratum_ok:
        ; Extract Transmit Timestamp: bytes 40-43 (big-endian NTP seconds)
        ld      hl, ntp_reply + 40
        ld      a, (hl)
        ld      (ntp_secs+0), a
        inc     hl
        ld      a, (hl)
        ld      (ntp_secs+1), a
        inc     hl
        ld      a, (hl)
        ld      (ntp_secs+2), a
        inc     hl
        ld      a, (hl)
        ld      (ntp_secs+3), a

        ; Subtract NTP epoch 0x83AA7E80 -> Unix time (little-endian in unix32)
        ld      a, (ntp_secs+3)
        ld      (unix32+0), a
        ld      a, (ntp_secs+2)
        ld      (unix32+1), a
        ld      a, (ntp_secs+1)
        ld      (unix32+2), a
        ld      a, (ntp_secs+0)
        ld      (unix32+3), a

        ld      hl, unix32
        ld      a, (hl)
        sub     0x80
        ld      (hl), a
        inc     hl
        ld      a, (hl)
        sbc     a, 0x7E
        ld      (hl), a
        inc     hl
        ld      a, (hl)
        sbc     a, 0xAA
        ld      (hl), a
        inc     hl
        ld      a, (hl)
        sbc     a, 0x83
        ld      (hl), a

        call    CONVERT_TIMESTAMP

        ; Display: YYYY-MM-DD HH:MM:SS UTC
        ld      hl, msg_time_is
        call    PRINT_STR
        ld      hl, (dt_year)
        call    PRINT_HL_DEC4
        ld      a, '-'
        call    TXT_OUTPUT
        ld      a, (dt_month)
        call    PRINT_BYTE_DEC2
        ld      a, '-'
        call    TXT_OUTPUT
        ld      a, (dt_day)
        call    PRINT_BYTE_DEC2
        ld      a, ' '
        call    TXT_OUTPUT
        ld      a, (dt_hour)
        call    PRINT_BYTE_DEC2
        ld      a, ':'
        call    TXT_OUTPUT
        ld      a, (dt_min)
        call    PRINT_BYTE_DEC2
        ld      a, ':'
        call    TXT_OUTPUT
        ld      a, (dt_sec)
        call    PRINT_BYTE_DEC2
        ld      hl, msg_utc
        call    PRINT_STR

ntp_close:
        ld      a, (my_socket)
        call    CLOSE

ntp_exit:
        ld      hl, ntp_msg_press_key
        call    PRINT_STR
        call    KM_WAIT_CHAR
        pop     iy
        ret

; =============================================================================
; ARITHMETIC
; =============================================================================

ZERO_MEM:
        xor     a
zm_loop:
        ld      (hl), a
        inc     hl
        dec     bc
        ld      a, b
        or      c
        jr      nz, zm_loop
        ret

; DIV32_BYTE: divide unix32 (32-bit LE in memory) by E (8-bit)
; Result: unix32 = quotient; A = remainder
; Processes bytes from MSB (unix32+3) to LSB (unix32+0)
DIV32_BYTE:
        push    hl
        push    bc
        push    de
        ld      c, e            ; C = divisor
        xor     a               ; A = running remainder (starts 0)
        ld      hl, unix32+3
        call    d32b_step
        dec     hl
        call    d32b_step
        dec     hl
        call    d32b_step
        dec     hl
        call    d32b_step
        pop     de
        pop     bc
        pop     hl
        ret

d32b_step:
        ; A = previous remainder, (HL) = current dividend byte
        ; Compute (A * 256 + byte) / C; store quotient in (HL), return remainder
        ld      b, a            ; B = high byte of 16-bit dividend
        ld      a, (hl)         ; A = low byte
        ld      d, 0            ; D = quotient byte (accumulate)
d32b_loop:
        ; If B > 0 or A >= C, subtract C once
        ld      e, a
        ld      a, b
        or      a
        ld      a, e
        jr      nz, d32b_big
        cp      c
        jr      c, d32b_done    ; A < C: finished
d32b_big:
        inc     d
        sub     c
        jr      nc, d32b_loop
        dec     b               ; borrow into high byte
        jr      d32b_loop
d32b_done:
        ld      (hl), d         ; store quotient byte
        ret                     ; A = remainder for next step

; =============================================================================
; CONVERT_TIMESTAMP: unix32 -> dt_year/month/day/hour/min/sec
; =============================================================================
CONVERT_TIMESTAMP:
        ; Sequential division extracts time fields and leaves day count
        ld      e, 60
        call    DIV32_BYTE          ; unix32 /= 60, A = seconds
        ld      (dt_sec), a

        ld      e, 60
        call    DIV32_BYTE          ; unix32 /= 60, A = minutes
        ld      (dt_min), a

        ld      e, 24
        call    DIV32_BYTE          ; unix32 /= 24, A = hours
        ld      (dt_hour), a

        ; unix32 now holds day count (fits in 16 bits for 1970-2149)
        ld      hl, (unix32)

        ; Find year
        ld      de, 1970
cvt_year:
        push    de
        call    LEAP_DAYS           ; carry set = leap (366 days)
        ld      bc, 366
        jr      c, cvt_sub_year
        ld      bc, 365
cvt_sub_year:
        or      a
        sbc     hl, bc
        jr      c, cvt_year_done
        pop     de
        inc     de
        jr      cvt_year
cvt_year_done:
        add     hl, bc              ; restore day-of-year (0-based)
        pop     de
        ld      (dt_year), de

        ; Leap flag for this year
        call    LEAP_DAYS
        ld      b, 0
        jr      nc, cvt_not_leap
        ld      b, 1
cvt_not_leap:

        ; Walk month table with IX; B = leap flag, C = month (1-based)
        ld      ix, month_days
        ld      c, 1
cvt_month:
        ld      a, (ix+0)
        or      a
        jr      z, cvt_month_done
        ld      e, a
        ld      d, 0
        ld      a, c
        cp      2
        jr      nz, cvt_do_sub
        ld      a, b                ; leap flag (also clears carry)
        or      a
        jr      z, cvt_do_sub
        ld      de, 29
cvt_do_sub:
        or      a
        sbc     hl, de
        jr      c, cvt_month_over
        inc     ix
        inc     c
        jr      cvt_month
cvt_month_over:
        add     hl, de
cvt_month_done:
        ld      a, c
        ld      (dt_month), a
        inc     hl
        ld      a, l
        ld      (dt_day), a
        ret

; LEAP_DAYS: DE = year -> carry set if leap year, carry clear if not
; Leap if divisible by 4, EXCEPT 2100 which is not a leap year
LEAP_DAYS:
        ld      a, e
        and     3
        ret     nz                  ; not div-by-4: not leap (carry clear from AND)
        ld      a, d
        cp      0x08
        jr      nz, ld_is_leap
        ld      a, e
        cp      0x34                ; 2100 = 0x0834
        jr      nz, ld_is_leap
        or      a                   ; 2100: not leap, carry clear
        ret
ld_is_leap:
        scf
        ret

; =============================================================================
; PRINT UTILITIES
; =============================================================================

PRINT_STR:
        ld      a, (hl)
        or      a
        ret     z
        call    TXT_OUTPUT
        inc     hl
        jr      PRINT_STR

PRINT_CRLF:
        ld      a, 0x0D
        call    TXT_OUTPUT
        ld      a, 0x0A
        call    TXT_OUTPUT
        ret

; Print 4-byte IP at HL as "a.b.c.d"
NTP_PRINT_IP:
        push    bc
        ld      b, 4
npi_loop:
        ld      a, (hl)
        inc     hl
        call    PRINT_BYTE_DEC
        dec     b
        jr      z, npi_done
        ld      a, '.'
        call    TXT_OUTPUT
        jr      npi_loop
npi_done:
        pop     bc
        ret

; Print byte in A as decimal (suppress leading zeros)
PRINT_BYTE_DEC:
        push    hl
        push    de
        push    bc
        ld      h, 0
        ld      l, a
        ld      de, 0
        call    pbd_100
        call    pbd_10
        ld      a, l
        add     a, '0'
        call    TXT_OUTPUT
        pop     bc
        pop     de
        pop     hl
        ret
pbd_100:
        ld      a, '0'-1
pbd_100s:
        inc     a
        ld      bc, -100
        add     hl, bc
        jr      c, pbd_100s
        ld      bc, 100
        add     hl, bc
        cp      '0'
        ret     z
        ld      de, 1
        call    TXT_OUTPUT
        ret
pbd_10:
        ld      a, '0'-1
pbd_10s:
        inc     a
        ld      bc, -10
        add     hl, bc
        jr      c, pbd_10s
        ld      bc, 10
        add     hl, bc
        cp      '0'
        ld      b, a
        ld      a, d
        or      e
        ld      a, b
        ret     z
        call    TXT_OUTPUT
        ld      de, 1
        ret

; Print byte in A as 2-digit decimal with leading zero
PRINT_BYTE_DEC2:
        push    hl
        push    bc
        ld      h, 0
        ld      l, a
        ld      a, '0'-1
pbd2_10:
        inc     a
        ld      bc, -10
        add     hl, bc
        jr      c, pbd2_10
        ld      bc, 10
        add     hl, bc
        call    TXT_OUTPUT
        ld      a, l
        add     a, '0'
        call    TXT_OUTPUT
        pop     bc
        pop     hl
        ret

; Print HL as 4-digit decimal with leading zeros (for year)
PRINT_HL_DEC4:
        push    bc
        push    de
        ld      de, 1000
        call    phd4_digit
        ld      de, 100
        call    phd4_digit
        ld      de, 10
        call    phd4_digit
        ld      a, l
        add     a, '0'
        call    TXT_OUTPUT
        pop     de
        pop     bc
        ret
phd4_digit:
        ld      a, '0'-1
phd4_sub:
        inc     a
        or      a
        sbc     hl, de
        jr      nc, phd4_sub
        add     hl, de
        call    TXT_OUTPUT
        ret

; =============================================================================
; CONFIGURATION
; =============================================================================

cfg_ntp_host:
        db      "time.cloudflare.com", 0

; =============================================================================
; VARIABLES
; =============================================================================

cfg_ntp_ip:     defs    4, 0
my_socket:      defb    0
ntp_packet:     defs    NTP_PKT_SIZE, 0
ntp_reply:      defs    NTP_PKT_SIZE, 0
peer_data:      defs    8, 0
ntp_secs:       defs    4, 0
unix32:         defs    4, 0

dt_year:        defw    0
dt_month:       defb    0
dt_day:         defb    0
dt_hour:        defb    0
dt_min:         defb    0
dt_sec:         defb    0

timeout_start:  defw    0

; =============================================================================
; CONSTANT DATA
; =============================================================================

month_days:
        db      31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 0

; =============================================================================
; MESSAGES
; =============================================================================

msg_banner:
        db      "NTP Client for CPC / Net4CPC", 0x0D, 0x0A
        db      "==============================", 0x0D, 0x0A, 0
msg_init:       db      "Initialising network...", 0
msg_ok:         db      " OK", 0x0D, 0x0A, 0
msg_resolving:  db      "Resolving: ", 0
msg_server_ip:  db      "NTP server IP: ", 0
msg_sending:    db      "Sending NTP request...", 0x0D, 0x0A, 0
msg_waiting:    db      "Waiting for reply...", 0x0D, 0x0A, 0
msg_time_is:    db      "UTC time: ", 0
msg_utc:        db      " UTC", 0x0D, 0x0A, 0
ntp_msg_press_key: db   "Press any key.", 0x0D, 0x0A, 0
msg_init_err:   db      "ERROR: Network init failed.", 0x0D, 0x0A, 0
msg_dns_err:    db      "ERROR: DNS failed.", 0x0D, 0x0A, 0
msg_sock_err:   db      "ERROR: Socket failed.", 0x0D, 0x0A, 0
msg_send_err:   db      "ERROR: Send failed.", 0x0D, 0x0A, 0
msg_timeout:    db      "ERROR: Timeout - no NTP reply.", 0x0D, 0x0A, 0
msg_dbg_sr:     db      "SR=", 0
msg_dbg_ir:     db      " IR=", 0
msg_dbg_rsr:    db      " RSR=", 0
msg_bad_reply:  db      "ERROR: Not an NTP server reply.", 0x0D, 0x0A, 0
msg_kod:        db      "ERROR: Kiss-o-Death packet received.", 0x0D, 0x0A, 0

; =============================================================================
; LIBRARY INCLUDES
; =============================================================================

        include "n4c-netinit-kv.s"
        include "w5100.s"
        include "dns_simple.s"

SAVE 'NTP.BIN',#4000,$-#4000,AMSDOS
