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

        org     &4000           ; standard CPC binary load address

; -----------------------------------------------------------------------------
; AMSDOS / Firmware entry points
; -----------------------------------------------------------------------------
TXT_OUTPUT      equ     &BB5A   ; output char in A to screen
KM_WAIT_CHAR    equ     &BB06   ; wait for keypress -> A
CAS_OUT_OPEN    equ     &BC8C   ; open file for output
CAS_OUT_CLOSE   equ     &BC92   ; close output file (flush + write EOF)
CAS_OUT_CHAR    equ     &BC9E   ; write byte in A to open output file
CAS_IN_OPEN     equ     &BC94   ; open file for input (existence test)
CAS_IN_CLOSE    equ     &BC98   ; close input file
TXT_CUR_OFF     equ     &BB84   ; turn cursor off
TXT_CUR_ON      equ     &BB87   ; turn cursor on

; -----------------------------------------------------------------------------
; n4c-nettools constants  (must match w5100.s)
; -----------------------------------------------------------------------------
SK_STREAM       equ     1       ; TCP socket type
SL_RECV         equ     1       ; SELECT: check for received data

; Receive buffer size - keep well within CPC RAM.
; With org &4000 and typical code size, &6000 onward is safe.
; Adjust if your code grows.
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
        ; Step 2: DNS resolution
        ; ------------------------------------------------------------------
        ld      hl, msg_resolving
        call    PRINT_STR
        ld      hl, cfg_host    ; null-terminated hostname
        call    PRINT_STR
        call    PRINT_CRLF

        ld      hl, cfg_host    ; Entry: HL = hostname (null-terminated)
        ld      de, server_ip   ; Entry: DE = 4-byte result buffer
        call    RESOLVE_HOSTNAME ; from dns_simple.s
        jr      nc, dns_ok
        ld      hl, msg_dns_err
        call    PRINT_STR
        jp      wget_exit

dns_ok:
        ld      hl, msg_resolved
        call    PRINT_STR
        ld      hl, server_ip
        call    PRINT_IP        ; show resolved IP
        call    PRINT_CRLF

        ; ------------------------------------------------------------------
        ; Step 3: Open TCP socket
        ; ------------------------------------------------------------------
        ld      hl, msg_connecting
        call    PRINT_STR

        ld      a, 0            ; socket number 0
        ld      d, SK_STREAM    ; TCP
        ld      e, 0            ; flags = 0
        call    SOCKET          ; from w5100.s
        jr      nc, sock_ok
        ld      hl, msg_sock_err
        call    PRINT_STR
        jp      wget_exit

sock_ok:
        ld      (my_socket), a  ; save socket handle

        ; ------------------------------------------------------------------
        ; Step 4: Connect to server
        ; ------------------------------------------------------------------
        ld      hl, server_ip   ; Entry: HL = 4-byte IP
        ld      bc, 80          ; Entry: BC = port number
        call    CONNECT         ; from w5100.s
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
        ; DE now points one past terminating null - compute length
        ld      hl, req_buf
        ; BC = DE - HL = request length (without null)
        ld      b, d
        ld      c, e
        or      a
        sbc     hl, bc          ; HL = -(length)  -- we need DE-req_buf
        ; Actually compute length properly:
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
        ; CAS_OUT_OPEN: HL=length of filename, DE=address of filename,
        ;               A=file type (&16 = BINARY for generic data)
        ;               BC= entry length (not used for type &16, set 0)
        ld      a, (cfg_fname_len)
        ld      h, 0
        ld      l, a            ; HL = filename length
        ld      de, cfg_fname   ; DE = filename string (no null needed by CAS)
        ld      a, &16          ; file type: unformatted binary / generic
        ld      bc, 0
        call    CAS_OUT_OPEN
        jr      nc, file_ok
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
        ; State variable 'hdr_done': 0 = still in headers, &FF = body mode
        ; ------------------------------------------------------------------
        xor     a
        ld      (hdr_done), a   ; start in header-scanning mode
        ld      (byte_count), a
        ld      (byte_count+1), a
        ld      (hdr_state), a  ; header scan state machine counter

recv_loop:
        ; Check if connection still alive first
        ld      a, (my_socket)
        call    CHECK_CONNECTION ; from w5100.s, nc=connected, c=closed
        jr      c, recv_done    ; server closed connection -> we're done

        ; Try to receive a chunk
        ld      hl, recv_buf
        ld      bc, RECV_BUF_SIZE
        call    NET_RECV        ; Entry: HL=buffer, BC=max bytes
                                ; Exit:  BC=bytes actually received, nc=ok, c=err/none
        jr      c, recv_loop    ; nothing yet (or error), keep polling
        ld      a, b
        or      c
        jr      z, recv_loop    ; zero bytes, keep polling

        ; Process the received chunk (BC bytes at recv_buf)
        ld      hl, recv_buf

process_chunk:
        ld      a, b
        or      c
        jr      z, recv_loop    ; chunk exhausted, get next

        ld      a, (hl)
        inc     hl
        dec     bc

        ; Are we already past the headers?
        ld      e, a            ; save byte
        ld      a, (hdr_done)
        or      a
        jr      nz, write_byte  ; yes - write directly

        ; Header scan state machine
        ; We look for the sequence CR LF CR LF (&0D &0A &0D &0A)
        ; State: 0=idle, 1=CR, 2=CRLF, 3=CRLFCR, 4=CRLFCRLF(done)
        ld      a, e            ; restore byte
        ld      d, a            ; keep copy
        ld      a, (hdr_state)

        ; state 0: waiting for first CR
        or      a
        jr      nz, hdr_s1
        ld      a, d
        cp      &0D
        jr      nz, process_chunk  ; not CR, stay in state 0 (bc already decremented)
        ld      a, 1
        ld      (hdr_state), a
        jr      process_chunk

hdr_s1: cp      1               ; got CR, waiting for LF
        jr      nz, hdr_s2
        ld      a, d
        cp      &0A
        jr      z, hdr_s1lf
        cp      &0D             ; another CR? stay in state 1
        jr      z, process_chunk
        xor     a               ; anything else: back to 0
        ld      (hdr_state), a
        jr      process_chunk
hdr_s1lf:
        ld      a, 2
        ld      (hdr_state), a
        jr      process_chunk

hdr_s2: cp      2               ; got CRLF, waiting for second CR
        jr      nz, hdr_s3
        ld      a, d
        cp      &0D
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
        cp      &0A
        jr      nz, hdr_reset
        ; Found CRLFCRLF - headers done!
        ld      a, &FF
        ld      (hdr_done), a
        jr      process_chunk   ; byte after separator goes to write_byte next iter

hdr_reset:
        xor     a
        ld      (hdr_state), a
        jr      process_chunk

write_byte:
        ; Write byte in E to AMSDOS output file
        ld      a, e
        call    CAS_OUT_CHAR
        jr      nc, write_ok
        ; Write error (disk full?)
        ld      hl, msg_disk_err
        call    PRINT_STR
        jp      file_close_err

write_ok:
        ; Increment 16-bit byte counter for progress display
        ld      hl, (byte_count)
        inc     hl
        ld      (byte_count), hl
        ; Print a dot every 512 bytes as progress indicator
        ld      a, l
        and     &01             ; every 512 bytes (bit 9 of counter toggling)
        ld      a, h
        and     &02
        or      l               ; crude: dot when low byte wraps
        ; simpler: just dot every 256 bytes (when L wraps to 0)
        ld      a, (byte_count) ; low byte
        or      a
        jr      nz, process_chunk
        ld      a, '.'
        call    TXT_OUTPUT
        jr      process_chunk

recv_done:
        call    PRINT_CRLF

        ; ------------------------------------------------------------------
        ; Step 8: Close file
        ; ------------------------------------------------------------------
        call    CAS_OUT_CLOSE
        jr      nc, close_ok
        ld      hl, msg_close_err
        call    PRINT_STR
        jp      wget_close

close_ok:
        ld      hl, msg_done
        call    PRINT_STR
        ; Print byte count
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
        ld      hl, msg_press_key
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
        ld      a, &0D
        call    TXT_OUTPUT
        ld      a, &0A
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

; PRINT_IP: print 4-byte IP address at HL as "a.b.c.d"
PRINT_IP:
        push    bc
        ld      b, 4
print_ip_loop:
        ld      a, (hl)
        inc     hl
        call    PRINT_BYTE_DEC
        dec     b
        jr      z, print_ip_done
        ld      a, '.'
        call    TXT_OUTPUT
        jr      print_ip_loop
print_ip_done:
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
        ; leading zero suppression flag in D: 0=suppress, &FF=print
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
        ld      d, &FF          ; leading zeros done
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

cfg_host        equ     &3E00           ; hostname from BASIC
cfg_path        equ     &3E80           ; path from BASIC
cfg_fname       equ     &3F00           ; AMSDOS filename from BASIC
cfg_fname_len   equ     &3F0B           ; address of filename length byte

; =============================================================================
; VARIABLES  (assembled into BSS-style area)
; =============================================================================

server_ip:      defs    4, 0    ; resolved IP address
my_socket:      defb    0       ; socket handle returned by SOCKET
hdr_done:       defb    0       ; &00 = in headers, &FF = in body
hdr_state:      defb    0       ; header CRLF detector state (0-3)
byte_count:     defw    0       ; bytes written to file

; HTTP request build buffer
; Max: "GET " + 255 + " HTTP/1.0\r\nHost: " + 255 + "\r\n\r\n" + null ~ 560 bytes
req_buf:        defs    600, 0

; Receive buffer (sits after req_buf)
recv_buf:       defs    RECV_BUF_SIZE, 0

; =============================================================================
; CONSTANT STRINGS
; =============================================================================

msg_banner:
        db      "WGET for CPC / Net4CPC", &0D, &0A
        db      "============================", &0D, &0A, 0
msg_init:
        db      "Initialising network...", 0
msg_ok:
        db      " OK", &0D, &0A, 0
msg_resolving:
        db      "Resolving: ", 0
msg_resolved:
        db      "Server IP: ", 0
msg_connecting:
        db      "Connecting to port 80...", 0
msg_connected:
        db      " OK", &0D, &0A, 0
msg_sending:
        db      "Sending GET request...", &0D, &0A, 0
msg_receiving:
        db      "Receiving", 0
msg_done:
        db      &0D, &0A, "Done! ", 0
msg_bytes:
        db      " bytes saved.", &0D, &0A, 0
msg_press_key:
        db      "Press any key.", &0D, &0A, 0

msg_init_err:
        db      "ERROR: N4C.CFG not found or bad config.", &0D, &0A, 0
msg_dns_err:
        db      "ERROR: DNS resolution failed.", &0D, &0A, 0
msg_sock_err:
        db      "ERROR: Could not open socket.", &0D, &0A, 0
msg_conn_err:
        db      "ERROR: Connection refused or timeout.", &0D, &0A, 0
msg_send_err:
        db      "ERROR: Send failed.", &0D, &0A, 0
msg_file_err:
        db      "ERROR: Could not open output file.", &0D, &0A, 0
msg_disk_err:
        db      "ERROR: Disk write failed (full?).", &0D, &0A, 0
msg_close_err:
        db      "ERROR: File close failed.", &0D, &0A, 0

http_get:       db      "GET ", 0
http_ver:       db      " HTTP/1.0", &0D, &0A, "Host: ", 0
http_end:       db      &0D, &0A, &0D, &0A, 0   ; blank line ends headers (CRLF CRLF)

; =============================================================================
; LIBRARY INCLUDES  (copy these files from n4c-nettools/src/ to your project)
; =============================================================================

        include "n4c-netinit-kv.s"
        include "w5100.s"
        include "dns_simple.s"

        end     WGET_START

; RASM output directive
SAVE 'WGET.BIN',#4000,$-#4000,AMSDOS
