; =============================================================================
; FOAL-HTTPD.S  —  Simple HTTP/1.0 server for Amstrad CPC / Net4CPC
;
; Listens on TCP port 80. For each incoming GET request:
;   - Extracts the filename from the URL path
;   - Opens the file from the AMSDOS disk using CAS_IN_OPEN / CAS_IN_CHAR
;   - Sends HTTP/1.0 200 OK + file data, or 404 if the file is not found
;   - Closes the connection and loops back to listen
;
; Press ESC to stop the server.
;
; Build flags:
;   -DAMSDOS_USB=1   Albireo / GoTek with USB/FAT Unidos ROMs (CAS IN +3)
;   (no flag)        ULIfAC, stock AMSDOS (standard CAS IN addresses)
;
; N4C.CFG is loaded by the BASIC loader (no CAS dependency for network init).
; CAS_IN is used for file serving and IS hardware-specific — use the right flag.
;
; Build (from src/foal-httpd/ after copying library files):
;   cp ../w5100.s ../n4c-netinit-kv.s .
;   rasm foal-httpd.s
;
; Usage: RUN"HTTPD
; =============================================================================

        org     0x4000

; Firmware entry points
TXT_OUTPUT      equ     0xBB5A      ; output char in A to screen
KM_WAIT_CHAR    equ     0xBB06      ; wait for keypress -> A
KM_READ_CHAR    equ     0xBB09      ; non-blocking read; carry set = char in A

; CAS INPUT routines.
; USB/FAT build (-DAMSDOS_USB=1): symbols defined by n4c-netinit-kv.s (0xBC77/7A/80).
; Standard build: defined here (0xBC74/77/7D).
IFNDEF AMSDOS_USB
CAS_IN_OPEN     equ     0xBC74
CAS_IN_CLOSE    equ     0xBC77
CAS_IN_CHAR     equ     0xBC7D
ENDIF

HTTP_PORT       equ     80
FILE_BUF_SIZE   equ     128
REQ_LINE_MAX    equ     128

; =============================================================================
; MAIN ENTRY POINT
; =============================================================================
HTTPD_START:
        push    iy

        ld      hl, msg_banner
        call    PRINT_STR

        ld      hl, msg_init
        call    PRINT_STR
        call    N4C_INIT
        jr      nc, .init_ok
        ld      hl, msg_init_err
        call    PRINT_STR
        jp      httpd_exit

.init_ok:
        ld      hl, msg_ok
        call    PRINT_STR

        ld      hl, msg_listening
        call    PRINT_STR

main_loop:
        call    HTTP_LISTEN
        jr      c, .listen_err

.wait_connect:
        call    KM_READ_CHAR
        jr      nc, .no_esc
        cp      'Q'
        jr      z, .stop
        cp      'q'
        jr      z, .stop
.no_esc:
        ld      hl, S0_SR
        call    W5100_READ_REG
        cp      SSTAT_ESTABLISHED
        jr      nz, .wait_connect

        ld      hl, msg_connected
        call    PRINT_STR

        call    HTTP_HANDLE_REQUEST
        jp      main_loop

.listen_err:
        ld      hl, msg_listen_err
        call    PRINT_STR
        jp      httpd_exit

.stop:
        ld      hl, msg_stopping
        call    PRINT_STR
        call    NET_CLOSE

httpd_exit:
        pop     iy
        ret

; =============================================================================
; HTTP_LISTEN — Open Socket 0 in TCP listen mode on HTTP_PORT
; Exit: carry clear = listening; carry set = error
; =============================================================================
HTTP_LISTEN:
        ; Force socket closed
        ld      hl, S0_CR
        ld      a, SCMD_CLOSE
        call    W5100_WRITE_REG
        call    WAIT_CMD_DONE

        ; Wait for SSTAT_CLOSED (0x00)
.wait_closed:
        ld      hl, S0_SR
        call    W5100_READ_REG
        or      a
        jr      nz, .wait_closed

        ; Clear interrupt flags
        ld      hl, S0_IR
        ld      a, 0xFF
        call    W5100_WRITE_REG

        ; TCP mode
        ld      hl, S0_MR
        ld      a, SMODE_TCP
        call    W5100_WRITE_REG

        ; Local port = HTTP_PORT (80 = 0x0050)
        ld      hl, S0_PORT0
        ld      a, HTTP_PORT >> 8
        call    W5100_WRITE_REG
        inc     hl
        ld      a, HTTP_PORT & 0xFF
        call    W5100_WRITE_REG

        ; Open
        ld      hl, S0_CR
        ld      a, SCMD_OPEN
        call    W5100_WRITE_REG
        call    WAIT_CMD_DONE

        ; Verify SSTAT_INIT
        ld      hl, S0_SR
        call    W5100_READ_REG
        cp      SSTAT_INIT
        jr      nz, .err

        ; Listen
        ld      hl, S0_CR
        ld      a, SCMD_LISTEN
        call    W5100_WRITE_REG
        call    WAIT_CMD_DONE

        or      a               ; clear carry = OK
        ret

.err:
        scf
        ret

; =============================================================================
; HTTP_HANDLE_REQUEST — Read, parse, and respond to one HTTP request
; =============================================================================
HTTP_HANDLE_REQUEST:
        call    HTTP_READ_REQUEST_LINE
        jr      c, .abort           ; connection closed before headers done

        call    HTTP_DRAIN_HEADERS
        jr      c, .abort           ; connection closed during headers

        call    HTTP_PARSE_PATH     ; fills fname_buf

        ld      hl, msg_serving
        call    PRINT_STR
        ld      hl, fname_buf
        call    PRINT_STR
        call    PRINT_CRLF

        call    HTTP_SERVE_FILE

.abort:
        call    NET_CLOSE
        ld      hl, msg_done
        call    PRINT_STR
        ret

; =============================================================================
; HTTP_READ_REQUEST_LINE — Read bytes into req_buf up to first LF
; Exit: carry clear = ok (req_buf null-terminated); carry set = disconnected
; =============================================================================
HTTP_READ_REQUEST_LINE:
        ld      hl, req_buf
        ld      b, REQ_LINE_MAX - 1

.read_char:
        push    bc
        push    hl
        call    HTTP_READ_BYTE
        pop     hl
        pop     bc
        jr      c, .disconnected

        ld      (hl), a
        inc     hl
        cp      0x0A                ; LF = end of request line
        jr      z, .done
        djnz    .read_char

.done:
        xor     a
        ld      (hl), a             ; null-terminate
        or      a                   ; clear carry
        ret

.disconnected:
        xor     a
        ld      (hl), a
        scf
        ret

; =============================================================================
; HTTP_DRAIN_HEADERS — Read and discard headers until \r\n\r\n
; State machine tracks the four-character sequence.
; =============================================================================
HTTP_DRAIN_HEADERS:
        xor     a
        ld      (drain_state), a

.loop:
        call    HTTP_READ_BYTE
        ret     c                   ; disconnected — give up silently

        ld      b, a                ; B = current byte
        ld      a, (drain_state)    ; A = state

        or      a
        jr      nz, .not_s0

        ; State 0 — looking for CR
        ld      a, b
        cp      0x0D
        ld      a, 1
        jr      z, .store
        xor     a
        jr      .store

.not_s0:
        cp      1
        jr      nz, .not_s1

        ; State 1 — looking for LF after CR
        ld      a, b
        cp      0x0A
        ld      a, 2
        jr      z, .store
        xor     a
        jr      .store

.not_s1:
        cp      2
        jr      nz, .not_s2

        ; State 2 — looking for second CR
        ld      a, b
        cp      0x0D
        ld      a, 3
        jr      z, .store
        xor     a
        jr      .store

.not_s2:
        ; State 3 — looking for final LF
        ld      a, b
        cp      0x0A
        ret     z                   ; \r\n\r\n complete — done
        xor     a                   ; unexpected byte — reset to state 0

.store:
        ld      (drain_state), a
        jr      .loop

; =============================================================================
; HTTP_READ_BYTE — Read one byte from Socket 0, blocking
; Exit: carry clear + A = byte; carry set = disconnected
; =============================================================================
HTTP_READ_BYTE:
.try:
        ld      hl, http_rxbyte
        ld      bc, 1
        call    NET_RECV            ; BC = 0 (no data) or 1 (got byte)
        ld      a, b
        or      c
        jr      nz, .got_byte

        ; No data — check connection state
        ld      hl, S0_SR
        call    W5100_READ_REG
        cp      SSTAT_ESTABLISHED
        jr      z, .try             ; still connected, keep polling
        ; CLOSE_WAIT or other = remote closed, no more data
        scf
        ret

.got_byte:
        ld      a, (http_rxbyte)
        or      a                   ; clear carry
        ret

; =============================================================================
; HTTP_PARSE_PATH — Extract CPC filename from req_buf into fname_buf
;
; req_buf contains the HTTP request line:
;   "GET /path/FILE.TXT HTTP/1.0\r\n\0"
;
; Strips the method, leading slash(es), and HTTP version; keeps only the
; last path segment; converts to uppercase for AMSDOS.
; Falls back to "INDEX.HTM" for bare "/" requests.
; =============================================================================
HTTP_PARSE_PATH:
        ld      hl, req_buf

        ; Skip method (scan to first space)
.skip_method:
        ld      a, (hl)
        or      a
        jr      z, .use_default     ; empty or malformed
        cp      ' '
        jr      z, .found_space
        inc     hl
        jr      .skip_method

.found_space:
        inc     hl                  ; skip the space itself

        ; Strip leading /
        ld      a, (hl)
        cp      '/'
        jr      nz, .copy_path
        inc     hl

        ; Walk path segments; keep a pointer to the start of the last one
.next_seg:
        push    hl                  ; save start of this segment

.scan_seg:
        ld      a, (hl)
        or      a
        jr      z, .end_of_seg
        cp      ' '
        jr      z, .end_of_seg
        cp      0x0D
        jr      z, .end_of_seg
        cp      0x0A
        jr      z, .end_of_seg
        cp      '?'
        jr      z, .end_of_seg
        cp      '/'
        jr      nz, .scan_next
        ; Found a slash — start a new segment
        pop     de                  ; discard saved start of previous segment
        inc     hl                  ; skip the slash
        jr      .next_seg

.scan_next:
        inc     hl
        jr      .scan_seg

.end_of_seg:
        pop     hl                  ; HL = start of last path segment

.copy_path:
        ld      de, fname_buf
        ld      b, 12               ; AMSDOS: max 8+1+3 = 12 printable chars

.copy_char:
        ld      a, (hl)
        or      a
        jr      z, .copy_done
        cp      ' '
        jr      z, .copy_done
        cp      0x0D
        jr      z, .copy_done
        cp      0x0A
        jr      z, .copy_done
        cp      '?'
        jr      z, .copy_done
        ; Convert to uppercase
        cp      'a'
        jr      c, .store_char
        cp      'z' + 1
        jr      nc, .store_char
        sub     'a' - 'A'
.store_char:
        ld      (de), a
        inc     hl
        inc     de
        djnz    .copy_char

.copy_done:
        xor     a
        ld      (de), a             ; null-terminate fname_buf

        ; Use default if filename is empty (bare "/" request)
        ld      a, (fname_buf)
        or      a
        ret     nz                  ; non-empty — done

.use_default:
        ld      hl, str_index_htm
        ld      de, fname_buf
        ld      bc, str_index_htm_len
        ldir
        ret

; =============================================================================
; HTTP_SERVE_FILE — Open file from disk and send over socket
; Sends 200 OK + file data, or 404 if not found.
; =============================================================================
HTTP_SERVE_FILE:
        ; Compute filename length for CAS_IN_OPEN
        ld      hl, fname_buf
        ld      b, 0
.len:
        ld      a, (hl)
        or      a
        jr      z, .open_file
        inc     hl
        inc     b
        jr      .len

.open_file:
        ; Defensive close in case a previous interrupted read left the CAS
        ; input channel occupied — CAS_IN_CLOSE is a no-op when nothing is open.
        call    CAS_IN_CLOSE

        ld      hl, fname_buf
        call    CAS_IN_OPEN         ; carry set = OK, carry clear = not found
        jr      nc, .not_found

        ; Pick Content-Type by extension (.HTM/.HTML → text/html, else text/plain)
        call    IS_HTML_EXT
        ld      hl, http_200_hdr_html
        ld      bc, http_200_hdr_html_end - http_200_hdr_html
        jr      z, .send_hdr
        ld      hl, http_200_hdr_plain
        ld      bc, http_200_hdr_plain_end - http_200_hdr_plain

.send_hdr:
        call    NET_SEND

        ; Read file in FILE_BUF_SIZE chunks, sending each.
        ; IY = remaining-byte safety counter (32 KB max) — prevents infinite
        ; CAS loops on files without a proper AMSDOS header.
        ; CHECK_CONNECTION before each flush stops the loop early if the peer
        ; closes the connection (e.g. browser gave up after receiving too much).
        ld      hl, file_buf
        ld      (file_buf_wr), hl
        ld      hl, 0x8000          ; 32 KB safety limit
        ld      (bytes_left), hl

.read_loop:
        ld      hl, (bytes_left)
        ld      a, h
        or      l
        jr      z, .eof             ; safety limit reached — treat as EOF

        call    CAS_IN_CHAR         ; carry set = byte in A; clear = EOF
        jr      nc, .eof

        ld      hl, (bytes_left)
        dec     hl
        ld      (bytes_left), hl

        ld      hl, (file_buf_wr)
        ld      (hl), a
        inc     hl
        ld      (file_buf_wr), hl

        ; Flush when buffer is full
        ld      de, file_buf + FILE_BUF_SIZE
        or      a
        sbc     hl, de
        jr      c, .read_loop       ; carry set = HL < end = room left

        ; Stop if peer already closed (e.g. CAS looping past real EOF)
        call    CHECK_CONNECTION
        jr      c, .cas_abort

        ld      hl, file_buf
        ld      bc, FILE_BUF_SIZE
        call    NET_SEND
        ld      hl, file_buf
        ld      (file_buf_wr), hl
        jr      .read_loop

.eof:
        ; Flush remaining bytes
        ld      hl, (file_buf_wr)
        ld      de, file_buf
        or      a
        sbc     hl, de              ; HL = bytes remaining in buffer
        ld      b, h
        ld      c, l
        ld      a, b
        or      c
        jr      z, .close_file
        ld      hl, file_buf
        call    NET_SEND

.close_file:
        call    CAS_IN_CLOSE
        ret

.cas_abort:
        ; Peer closed before CAS signalled EOF — close file and bail
        call    CAS_IN_CLOSE
        ret

.not_found:
        ld      hl, http_404_resp
        ld      bc, http_404_resp_end - http_404_resp
        call    NET_SEND
        ret

; =============================================================================
; IS_HTML_EXT — Test whether fname_buf ends in .HTM or .HTML
; Exit: Z set if HTML extension, Z clear otherwise
; Corrupts: A, HL, BC
; =============================================================================
IS_HTML_EXT:
        ; Find end of fname_buf
        ld      hl, fname_buf
.scan:
        ld      a, (hl)
        or      a
        jr      z, .at_end
        inc     hl
        jr      .scan
.at_end:
        ; HL points to the null terminator. Back up to find the dot.
        ; Check last 4 chars for ".HTM\0" or last 5 for ".HTML\0"
        ; Strategy: check byte at (HL-4) for '.' then (HL-3..HL-1) for HTM
        push    hl

        ; Try ".HTM" — 4 chars before null: . H T M
        ld      bc, -4
        add     hl, bc              ; HL → char at position (end-4)
        ld      a, (hl)
        cp      '.'
        jr      nz, .not_htm_short
        inc     hl
        ld      a, (hl)
        cp      'H'
        jr      nz, .not_htm_short
        inc     hl
        ld      a, (hl)
        cp      'T'
        jr      nz, .not_htm_short
        inc     hl
        ld      a, (hl)
        cp      'M'
        jr      nz, .not_htm_short
        ; Matched ".HTM"
        pop     hl
        xor     a                   ; Z set
        ret

.not_htm_short:
        pop     hl
        push    hl

        ; Try ".HTML" — 5 chars before null: . H T M L
        ld      bc, -5
        add     hl, bc
        ld      a, h
        or      l
        jr      z, .no_html         ; pointer underflowed (name too short)
        ld      a, (hl)
        cp      '.'
        jr      nz, .no_html
        inc     hl
        ld      a, (hl)
        cp      'H'
        jr      nz, .no_html
        inc     hl
        ld      a, (hl)
        cp      'T'
        jr      nz, .no_html
        inc     hl
        ld      a, (hl)
        cp      'M'
        jr      nz, .no_html
        inc     hl
        ld      a, (hl)
        cp      'L'
        jr      nz, .no_html
        ; Matched ".HTML"
        pop     hl
        xor     a                   ; Z set
        ret

.no_html:
        pop     hl
        or      1                   ; Z clear
        ret

; =============================================================================
; PRINT utilities
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

; =============================================================================
; Variables
; =============================================================================
drain_state:    defb    0
http_rxbyte:    defb    0
file_buf_wr:    defw    0
bytes_left:     defw    0           ; safety byte counter for file read loop

; =============================================================================
; Buffers
; =============================================================================
req_buf:        defs    REQ_LINE_MAX, 0
fname_buf:      defs    16, 0
file_buf:       defs    FILE_BUF_SIZE, 0

; =============================================================================
; Constant data
; =============================================================================
str_index_htm:
        db      "INDEX.HTM", 0
str_index_htm_len equ $ - str_index_htm

http_200_hdr_html:
        db      "HTTP/1.0 200 OK", 0x0D, 0x0A
        db      "Content-Type: text/html", 0x0D, 0x0A
        db      "Connection: close", 0x0D, 0x0A
        db      0x0D, 0x0A
http_200_hdr_html_end:

http_200_hdr_plain:
        db      "HTTP/1.0 200 OK", 0x0D, 0x0A
        db      "Content-Type: text/plain", 0x0D, 0x0A
        db      "Connection: close", 0x0D, 0x0A
        db      0x0D, 0x0A
http_200_hdr_plain_end:

http_404_resp:
        db      "HTTP/1.0 404 Not Found", 0x0D, 0x0A
        db      "Content-Type: text/plain", 0x0D, 0x0A
        db      "Connection: close", 0x0D, 0x0A
        db      0x0D, 0x0A
        db      "404 Not Found", 0x0D, 0x0A
http_404_resp_end:

; =============================================================================
; Messages
; =============================================================================
msg_banner:
        db      "FOAL-HTTPD / Net4CPC", 0x0D, 0x0A
        db      "====================", 0x0D, 0x0A, 0
msg_init:
        db      "Initialising network...", 0
msg_ok:
        db      " OK", 0x0D, 0x0A, 0
msg_listening:
        db      "Listening on port 80. Press Q to exit.", 0x0D, 0x0A, 0
msg_connected:
        db      "Connection received.", 0x0D, 0x0A, 0
msg_serving:
        db      "Serving: ", 0
msg_done:
        db      "Done.", 0x0D, 0x0A, 0
msg_init_err:
        db      "ERROR: Network init failed.", 0x0D, 0x0A, 0
msg_listen_err:
        db      "ERROR: Listen failed.", 0x0D, 0x0A, 0
msg_stopping:
        db      "Stopping.", 0x0D, 0x0A, 0

; =============================================================================
; Library includes
; =============================================================================
        include "n4c-netinit-kv.s"
        include "w5100.s"

IFDEF AMSDOS_USB
SAVE 'HTTPDALB.BIN',#4000,$-#4000,AMSDOS
ELSE
SAVE 'HTTPDSTD.BIN',#4000,$-#4000,AMSDOS
ENDIF
