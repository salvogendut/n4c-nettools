; =============================================================================
; WGET.S  -  Simple HTTP file downloader for Amstrad CPC / AMSDOS
;            Uses n4c-nettools (salvogendut/n4c-nettools) library
;
; Build:
;   cd drafts
;   ./build_wget.sh
;
; Usage:
;   Run WGET.BAS which will:
;     1. Prompt for URL (e.g., "http://example.com/files/test.txt")
;     2. Parse URL into hostname, path, and filename
;     3. Write these to memory (&3E00-&3F0B)
;     4. Load and call this binary
;
; The binary reads URL components from memory locations:
;   &3E00: Hostname (null-terminated)
;   &3E80: Path (null-terminated)
;   &3F00: AMSDOS filename (11 bytes, space-padded)
;   &3F0B: Filename length (1 byte)
;
; Requires N4C.CFG on the same disk:
;   IP=192.168.1.100
;   MASK=255.255.255.0
;   GW=192.168.1.1
;   DNS=8.8.8.8
;
; Library files needed for building:
;   w5100.s          - from n4c-nettools/src/
;   dns_simple.s     - from n4c-nettools/src/
;   n4c-netinit-kv.s - from n4c-nettools/src/
; =============================================================================

        org     0x4000          ; standard CPC binary load address

; -----------------------------------------------------------------------------
; AMSDOS / Firmware entry points
; -----------------------------------------------------------------------------
TXT_OUTPUT      equ     0xBB5A  ; output char in A to screen
KM_WAIT_CHAR    equ     0xBB06  ; wait for keypress -> A
; GoTek/AMSDOS: CAS INPUT routines shifted +3 from standard (one extra entry
; inserted before IN section). CAS OUTPUT routines stay at standard addresses.
; Confirmed: CAS_IN_OPEN standard &BC74 -> GoTek &BC77 (+3)
;            CAS_OUT_OPEN standard &BC8C -> GoTek &BC8C (no shift, confirmed working)
CAS_OUT_OPEN    equ     0xBC8C  ; standard address, no shift
CAS_OUT_CLOSE   equ     0xBC8F  ; standard address, no shift
CAS_OUT_CHAR    equ     0xBC95  ; standard address, no shift (was wrongly &BC92 = ABANDON)

; -----------------------------------------------------------------------------
; Receive buffer size - keep well within CPC RAM.
; With org 0x4000 and typical code size, 0x6000 onward is safe.
; -----------------------------------------------------------------------------
RECV_BUF_SIZE   equ     512     ; bytes per NET_RECV call

; =============================================================================
; MAIN ENTRY POINT
; =============================================================================
WGET_START:
        ; Preserve BASIC's IY (firmware uses it)
        push    iy

        ; Say hello
        ld      hl, msg_banner
        call    PRINT_STR

        ; ------------------------------------------------------------------
        ; Step 1: Initialise network from N4C.CFG
        ; ------------------------------------------------------------------
        ld      hl, msg_init
        call    PRINT_STR

        call    N4C_INIT        ; from n4c-netinit-kv.s
        jr      nc, init_ok
        ld      hl, msg_init_err
        call    PRINT_STR
        jp      wget_exit

init_ok:
        ld      hl, msg_ok
        call    PRINT_STR

        ; ------------------------------------------------------------------
        ; Step 2: Resolve hostname or parse dotted IP directly
        ; ------------------------------------------------------------------
        ; If hostname starts with a digit it's a dotted IP - skip DNS
        ld      a, (cfg_host)
        cp      '0'
        jp      c, do_dns
        cp      '9'+1
        jp      nc, do_dns

        ld      hl, cfg_host
        ld      de, server_ip
        call    PARSE_DOTTED_IP
        jr      dns_ok

do_dns:
        ld      hl, msg_resolving
        call    PRINT_STR
        ld      hl, cfg_host
        call    PRINT_STR
        call    PRINT_CRLF
        ld      hl, cfg_host
        ld      de, server_ip
        call    RESOLVE_HOSTNAME
        jr      nc, dns_ok
        ld      hl, msg_dns_err
        call    PRINT_STR
        jp      wget_exit

dns_ok:
        ld      hl, msg_resolved
        call    PRINT_STR
        ld      hl, server_ip
        call    WGET_PRINT_IP
        call    PRINT_CRLF

        ; ------------------------------------------------------------------
        ; Step 3: Open TCP socket 0
        ; ------------------------------------------------------------------
        ld      hl, msg_connecting
        call    PRINT_STR

        ld      a, 0            ; socket number 0
        ld      b, 1            ; TCP protocol
        call    NET_SOCKET      ; from w5100.s
        jr      nc, sock_ok
        ld      hl, msg_sock_err
        call    PRINT_STR
        jp      wget_exit

sock_ok:
        xor     a
        ld      (my_socket), a  ; socket 0 (NET_SOCKET doesn't return a number)

        ; ------------------------------------------------------------------
        ; Step 4: Connect to server
        ; ------------------------------------------------------------------
        ld      hl, server_ip   ; Entry: HL = 4-byte IP
        ld      hl, (cfg_port)  ; load port (little-endian: L=low byte, H=high byte)
        ld      b, h            ; B = high byte of port (NET_CONNECT wants B=high)
        ld      c, l            ; C = low byte of port
        ld      hl, server_ip
        call    NET_CONNECT     ; from w5100.s
        jr      nc, conn_ok
        ld      hl, msg_conn_err
        call    PRINT_STR
        jp      wget_close

conn_ok:
        ld      hl, msg_connected
        call    PRINT_STR

        ; ------------------------------------------------------------------
        ; Step 5: Build and send HTTP/1.0 GET request
        ;
        ; HTTP/1.0 is intentionally used - server closes connection after
        ; response, giving us a clean EOF signal (connection drops).
        ; Format:
        ;   GET /path HTTP/1.0\r\n
        ;   Host: hostname\r\n
        ;   \r\n
        ; ------------------------------------------------------------------
        ld      hl, msg_sending
        call    PRINT_STR

        ; Assemble request into req_buf
        ld      de, req_buf
        ld      hl, http_get            ; "GET "
        call    STRCPY_DE
        ld      hl, cfg_path            ; "/path/to/file"
        call    STRCPY_DE
        ld      hl, http_ver            ; " HTTP/1.0\r\nHost: "
        call    STRCPY_DE
        ld      hl, cfg_host            ; "hostname"
        call    STRCPY_DE
        ld      hl, http_end            ; "\r\n\r\n"
        call    STRCPY_DE
        ; Compute request length
        ld      hl, req_buf
        ld      b, 0
        ld      c, 0
req_len_loop:
        ld      a, (hl)
        or      a
        jr      z, req_len_done
        inc     hl
        inc     bc
        jr      req_len_loop
req_len_done:
        ; BC = length, now send
        ld      hl, req_buf
        call    NET_SEND        ; Entry: HL=data, BC=length  (w5100.s)
        jr      nc, send_ok
        ld      hl, msg_send_err
        call    PRINT_STR
        jp      wget_close

send_ok:
        ld      hl, msg_receiving
        call    PRINT_STR

        ; ------------------------------------------------------------------
        ; Step 6: Open local output file
        ; ------------------------------------------------------------------
        ; CAS_OUT_OPEN: B=length of filename, HL=address of filename,
        ;               A=file type (2=binary)
        ; Carry SET = success, Carry CLEAR = failure
        ld      a, (cfg_fname_len)
        ld      b, a            ; B = filename length
        ld      hl, cfg_fname   ; HL = filename address
        ld      a, 2            ; file type: binary
        call    CAS_OUT_OPEN
        jr      c, file_ok
        ld      hl, msg_file_err
        call    PRINT_STR
        jp      wget_close

file_ok:
        ; ------------------------------------------------------------------
        ; Step 7: Receive loop
        ;
        ; We receive chunks into recv_buf, scan for end of HTTP headers
        ; (\r\n\r\n), then write only the body bytes to the file.
        ;
        ; State variable 'hdr_done': 0 = still in headers, 0xFF = body mode
        ; ------------------------------------------------------------------
        xor     a
        ld      (byte_count), a
        ld      (byte_count+1), a
        ld      (hdr_state), a  ; header scan state machine counter
        ld      a, 0xFF
        ld      (hdr_done), a   ; DEBUG: skip header parsing, write everything to disk

recv_loop:
        ; Always try to receive data before checking connection state.
        ; The W5100S buffers data that arrived before the server's FIN;
        ; checking connection first would cause us to jump to recv_done
        ; and miss that buffered data.
        ld      hl, recv_buf
        ld      bc, RECV_BUF_SIZE
        call    NET_RECV        ; Entry: HL=buffer, BC=max bytes
                                ; Exit:  BC=bytes actually received, nc=ok, c=none
        jp      c, recv_chkconn ; no data right now - check connection state
        ld      a, b
        or      c
        jp      z, recv_chkconn ; zero bytes - check connection state

        ; Data received - process the chunk (BC bytes starting at recv_buf)
        ld      hl, recv_buf

process_chunk:
        ld      a, b
        or      c
        jp      z, recv_chkconn ; chunk exhausted - check for more or connection close

        ld      a, (hl)
        inc     hl
        dec     bc

        ; Diagnostic: echo first 80 received bytes to screen as-is
        push    af
        ld      a, (dbg_left)
        or      a
        jr      z, dbg_skip
        dec     a
        ld      (dbg_left), a
        pop     af
        push    af
        call    TXT_OUTPUT      ; print raw byte (shows HTTP response on screen)
dbg_skip:
        pop     af

        ; Are we already past the headers?
        ld      e, a            ; save byte
        ld      a, (hdr_done)
        or      a
        jr      nz, write_byte  ; yes - write directly

        ; Header scan state machine
        ; We look for the sequence CR LF CR LF (0x0D 0x0A 0x0D 0x0A)
        ; State: 0=idle, 1=CR, 2=CRLF, 3=CRLFCR, 4=CRLFCRLF(done)
        ld      a, e            ; restore byte
        ld      d, a            ; keep copy
        ld      a, (hdr_state)

        ; state 0: waiting for first CR
        or      a
        jr      nz, hdr_s1
        ld      a, d
        cp      0x0D
        jr      nz, process_chunk
        ld      a, 1
        ld      (hdr_state), a
        jr      process_chunk

hdr_s1: cp      1               ; got CR, waiting for LF
        jr      nz, hdr_s2
        ld      a, d
        cp      0x0A
        jr      z, hdr_s1lf
        cp      0x0D            ; another CR? stay in state 1
        jp      z, process_chunk
        xor     a               ; anything else: back to 0
        ld      (hdr_state), a
        jp      process_chunk
hdr_s1lf:
        ld      a, 2
        ld      (hdr_state), a
        jr      process_chunk

hdr_s2: cp      2               ; got CRLF, waiting for second CR
        jr      nz, hdr_s3
        ld      a, d
        cp      0x0D
        jr      z, hdr_s2cr
        xor     a
        ld      (hdr_state), a
        jr      process_chunk
hdr_s2cr:
        ld      a, 3
        ld      (hdr_state), a
        jr      process_chunk

hdr_s3: cp      3               ; got CRLFCR, waiting for final LF
        jr      nz, hdr_reset
        ld      a, d
        cp      0x0A
        jr      nz, hdr_reset
        ; Found CRLFCRLF - headers done!
        ld      a, 0xFF
        ld      (hdr_done), a
        jr      process_chunk

hdr_reset:
        xor     a
        ld      (hdr_state), a
        jr      process_chunk

write_byte:
        ; Write byte in E to AMSDOS output file.
        ; CAS_OUT_CHAR trashes HL and BC, so save/restore the recv_buf
        ; pointer (HL) and remaining-bytes counter (BC) around the call.
        push    hl              ; save recv_buf pointer
        push    bc              ; save remaining byte count
        ld      a, e
        call    CAS_OUT_CHAR
        pop     bc              ; restore remaining count
        pop     hl              ; restore recv_buf pointer
        jr      c, write_ok
        ; Write error (disk full?)
        ld      hl, msg_disk_err
        call    PRINT_STR
        jp      file_close_err

write_ok:
        ; Increment 16-bit byte counter; print a dot every 256 bytes.
        ; Must keep HL (recv_buf ptr) and BC (remaining count) intact.
        push    hl
        push    bc
        ld      hl, (byte_count)
        inc     hl
        ld      (byte_count), hl
        ld      a, l
        pop     bc
        pop     hl
        or      a
        jp      nz, process_chunk
        ld      a, '.'
        call    TXT_OUTPUT      ; preserves HL, BC per firmware convention
        jp      process_chunk

recv_chkconn:
        ; No data from NET_RECV - check whether the server has closed.
        ; Only exit when both conditions are true: no data AND connection gone.
        ld      a, (my_socket)
        call    CHECK_CONNECTION
        jp      c, recv_done    ; closed (CLOSE_WAIT or CLOSED) → done
        jp      recv_loop       ; still open → keep polling

recv_done:
        call    PRINT_CRLF

        ; ------------------------------------------------------------------
        ; Step 8: Close file
        ; ------------------------------------------------------------------
        call    CAS_OUT_CLOSE
        jr      c, close_ok
        ld      hl, msg_close_err
        call    PRINT_STR
        jp      wget_close

close_ok:
        ld      hl, msg_done
        call    PRINT_STR
        ld      hl, (byte_count)
        call    PRINT_HL_DEC
        ld      hl, msg_bytes
        call    PRINT_STR
        jr      wget_close

file_close_err:
        call    CAS_OUT_CLOSE   ; best effort

wget_close:
        ; Close TCP socket
        ld      a, (my_socket)
        call    CLOSE           ; from w5100.s

wget_exit:
        ld      hl, wget_msg_press_key
        call    PRINT_STR
        call    KM_WAIT_CHAR

        pop     iy              ; restore BASIC's IY
        ret                     ; back to BASIC

; =============================================================================
; UTILITY ROUTINES
; =============================================================================

; PRINT_STR: print null-terminated string at HL
PRINT_STR:
        ld      a, (hl)
        or      a
        ret     z
        call    TXT_OUTPUT
        inc     hl
        jr      PRINT_STR

; PRINT_CRLF: print CR+LF
PRINT_CRLF:
        ld      a, 0x0D
        call    TXT_OUTPUT
        ld      a, 0x0A
        call    TXT_OUTPUT
        ret

; STRCPY_DE: append null-terminated string at HL to buffer pointed by DE
;            DE advances to point at the null terminator
STRCPY_DE:
        ld      a, (hl)
        ld      (de), a
        or      a
        ret     z
        inc     hl
        inc     de
        jr      STRCPY_DE

; PARSE_DOTTED_IP: parse "a.b.c.d" string at HL into 4 bytes at DE
; parse_decimal_byte (from n4c-netinit-kv.s) clobbers DE, so save/restore it
PARSE_DOTTED_IP:
        push    bc
        ld      b, 4
pdip_octet:
        push    de                  ; save dest pointer - parse_decimal_byte trashes DE
        call    parse_decimal_byte  ; A = octet, HL advanced past digits
        pop     de                  ; restore dest pointer
        ld      (de), a
        inc     de
        dec     b
        jr      z, pdip_done
        inc     hl                  ; skip '.'
        jr      pdip_octet
pdip_done:
        pop     bc
        ret

; WGET_PRINT_IP: print 4-byte IP address at HL as "a.b.c.d"
WGET_PRINT_IP:
        push    bc
        ld      b, 4
wget_ip_loop:
        ld      a, (hl)
        inc     hl
        call    PRINT_BYTE_DEC
        dec     b
        jr      z, wget_ip_done
        ld      a, '.'
        call    TXT_OUTPUT
        jr      wget_ip_loop
wget_ip_done:
        pop     bc
        ret

; PRINT_BYTE_DEC: print byte in A as decimal (0-255)
PRINT_BYTE_DEC:
        push    hl
        push    bc
        push    de
        ld      h, 0
        ld      l, a
        call    PRINT_HL_DEC
        pop     de
        pop     bc
        pop     hl
        ret

; PRINT_HL_DEC: print HL as unsigned decimal
PRINT_HL_DEC:
        push    bc
        push    de
        push    af
        ld      d, 0            ; leading-zero suppression flag: 0=suppress
        ld      bc, -10000
        call    phdec_digit
        ld      bc, -1000
        call    phdec_digit
        ld      bc, -100
        call    phdec_digit
        ld      bc, -10
        call    phdec_digit
        ld      a, l
        add     a, '0'
        call    TXT_OUTPUT
        pop     af
        pop     de
        pop     bc
        ret
phdec_digit:
        ld      a, '0'-1
phdec_sub:
        inc     a
        add     hl, bc
        jr      c, phdec_sub
        sbc     hl, bc          ; undo last subtract
        cp      '0'
        jr      nz, phdec_print
        ld      e, a            ; save digit
        ld      a, d
        or      a
        ret     z               ; suppress leading zero
        ld      a, e
phdec_print:
        ld      d, 0xFF         ; leading zeros done
        call    TXT_OUTPUT
        ret

; =============================================================================
; CONFIGURATION  -  Passed from BASIC via memory
; =============================================================================
; Memory layout (populated by WGET.BAS):
;   &3E00: Hostname (null-terminated, max 128 bytes)
;   &3E80: Path (null-terminated, max 128 bytes)
;   &3F00: AMSDOS filename (11 bytes, space-padded)
;   &3F0B: Filename length (1 byte)

cfg_host        equ     0x3E00          ; hostname from BASIC
cfg_path        equ     0x3E80          ; path from BASIC
cfg_fname       equ     0x3F00          ; AMSDOS filename from BASIC
cfg_fname_len   equ     0x3F0B          ; address of filename length byte
cfg_port        equ     0x3F0C          ; port number from BASIC (16-bit little-endian)

; =============================================================================
; VARIABLES  (assembled into BSS-style area)
; =============================================================================

server_ip:      defs    4, 0    ; resolved IP address
my_socket:      defb    0       ; socket handle (always 0 for TCP)
hdr_done:       defb    0       ; 0x00 = in headers, 0xFF = in body
hdr_state:      defb    0       ; header CRLF detector state (0-3)
byte_count:     defw    0       ; bytes written to file
dbg_left:       defb    80      ; diagnostic: bytes left to echo to screen

; HTTP request build buffer
; Max: "GET " + 255 + " HTTP/1.0\r\nHost: " + 255 + "\r\n\r\n" + null ~ 560 bytes
req_buf:        defs    600, 0

; Receive buffer (sits after req_buf)
recv_buf:       defs    RECV_BUF_SIZE, 0

; =============================================================================
; CONSTANT STRINGS
; =============================================================================

msg_banner:
        db      "WGET for CPC / Net4CPC", 0x0D, 0x0A
        db      "============================", 0x0D, 0x0A, 0
msg_init:
        db      "Initialising network...", 0
msg_ok:
        db      " OK", 0x0D, 0x0A, 0
msg_resolving:
        db      "Resolving: ", 0
msg_resolved:
        db      "Server IP: ", 0
msg_connecting:
        db      "Connecting...", 0
msg_connected:
        db      " OK", 0x0D, 0x0A, 0
msg_sending:
        db      "Sending GET request...", 0x0D, 0x0A, 0
msg_receiving:
        db      "Receiving", 0
msg_done:
        db      0x0D, 0x0A, "Done! ", 0
msg_bytes:
        db      " bytes saved.", 0x0D, 0x0A, 0
wget_msg_press_key:
        db      "Press any key.", 0x0D, 0x0A, 0

msg_init_err:
        db      "ERROR: N4C.CFG not found or bad config.", 0x0D, 0x0A, 0
msg_dns_err:
        db      "ERROR: DNS resolution failed.", 0x0D, 0x0A, 0
msg_sock_err:
        db      "ERROR: Could not open socket.", 0x0D, 0x0A, 0
msg_conn_err:
        db      "ERROR: Connection refused or timeout.", 0x0D, 0x0A, 0
msg_send_err:
        db      "ERROR: Send failed.", 0x0D, 0x0A, 0
msg_file_err:
        db      "ERROR: Could not open output file.", 0x0D, 0x0A, 0
msg_disk_err:
        db      "ERROR: Disk write failed (full?).", 0x0D, 0x0A, 0
msg_close_err:
        db      "ERROR: File close failed.", 0x0D, 0x0A, 0

http_get:       db      "GET ", 0
http_ver:       db      " HTTP/1.0", 0x0D, 0x0A, "Host: ", 0
http_end:       db      0x0D, 0x0A, 0x0D, 0x0A, 0

; =============================================================================
; LIBRARY INCLUDES  (copy these files from n4c-nettools/src/ to your project)
; =============================================================================

        include "n4c-netinit-kv.s"
        include "w5100.s"
        include "dns_simple.s"

SAVE 'WGET.BIN',#4000,$-#4000,AMSDOS
