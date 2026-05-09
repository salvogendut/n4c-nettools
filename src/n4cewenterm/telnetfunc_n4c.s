; Telnet functionality for Net4CPC
; Adapted from M4EWENTERM telnetfunc2.s
; Uses W5100S socket interface instead of M4 commands

start_telnet:
    ld hl, msgtest
    call disptextz
    call drawline
    call Check_n4c
    call loop_ip

telnet_session:
    ; Create TCP socket
    ld hl, msgdebug_socket
    call disptextz

    ld a, 0             ; Socket 0
    ld b, 1             ; TCP protocol
    call NET_SOCKET
    jp c, socket_error

    ld hl, msgdebug_socket_ok
    call disptextz

    ; Connect to server
    ld hl, msgdebug_connect
    call disptextz

    ; Debug: show port value loaded from memory
    ld hl, msgdebug_port_loaded
    call disptextz
    ld bc, (port)       ; Port number
    push bc
    ld a, b
    call disp_hex_byte
    ld a, c
    call disp_hex_byte
    ld a, ' '
    call printchar
    ld a, '('
    call printchar
    pop bc
    push bc
    push bc
    ld h, b
    ld l, c
    call disp_dec16
    pop bc
    ld a, ')'
    call printchar
    call crlf
    pop bc

    ld hl, ip_addr      ; Pointer to IP address
    call NET_CONNECT

    ; Debug: read back what W5100S has for destination
    push af
    ld hl, msgdebug_dest_ip
    call disptextz
    ld hl, S0_DIPR0
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, S0_DIPR1
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, S0_DIPR2
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, S0_DIPR3
    call W5100_READ_REG
    call disp_dec
    call crlf

    ld hl, msgdebug_dest_port
    call disptextz
    ld hl, S0_DPORT0
    call W5100_READ_REG
    ld h, a             ; H = high byte
    ld hl, S0_DPORT1
    call W5100_READ_REG
    ld l, a             ; L = low byte
    ; Now HL has the port number (but HL register was used as temp)
    ; Need to rebuild HL properly
    push af
    ld hl, S0_DPORT0
    call W5100_READ_REG
    ld d, a             ; D = high byte
    ld hl, S0_DPORT1
    call W5100_READ_REG
    ld e, a             ; E = low byte
    ; DE now has port
    ex de, hl           ; Move to HL for display
    call disp_dec16
    pop af
    call crlf
    pop af

    jp c, connect_error

connect_ok:
    ld hl, msgconnect
    call disptextz

    ; Clear any debug messages
    ld hl, msgready
    call disptextz

    ; Initialize telnet state machine
    xor a
    ld (telnet_iac_state), a

    ; Initialize local echo as enabled (server will negotiate if needed)
    ld a, 1
    ld (local_echo_enabled), a

mainloop:
    ; Check for received data
    call recv_noblock2

    ; Check keyboard
    call km_read_char
    jr nc, mainloop

    cp 27               ; ESC? (now returns ASCII 27 after translation)
    jp z, exit_close
    cp 0x9              ; TAB?
    jr nz, no_pause

wait_no_tab:
    call km_read_char
    cp 0x9
    jr z, wait_no_tab

pause_loop:
    call km_read_char
    cp 27               ; ESC?
    jp z, exit_close
    cp 0x9              ; TAB again to leave
    jr nz, pause_loop
    jr mainloop

no_pause:
    ; Store the character
    ld hl, sendtext
    ld (hl), a

    ; Check if it's ENTER (CR)
    cp 0xD
    jr z, is_enter

    ; Check if local echo is enabled
    push af
    ld a, (local_echo_enabled)
    or a
    jp z, no_local_echo

    ; Local echo enabled - display the character
    pop af
    push af
    ld b, a
    call printchar

no_local_echo:
    pop af

    ; Send single character
    ld hl, sendtext
    ld bc, 1
    call NET_SEND
    jp mainloop

is_enter:
    ; Check if local echo is enabled
    ld a, (local_echo_enabled)
    or a
    jp z, no_echo_enter

    ; Echo CR+LF locally
    ld a, 13
    ld b, a
    call printchar
    ld a, 10
    ld b, a
    call printchar

no_echo_enter:
    ; Send CR+LF to server
    ld hl, sendtext
    ld (hl), 0xD
    inc hl
    ld (hl), 0xA
    ld hl, sendtext
    ld bc, 2
    call NET_SEND
    jp mainloop

recv_noblock2:
    push af
    push bc
    push de
    push hl

    ; Check connection once per call, not per byte
    call CHECK_CONNECTION
    jr nc, .still_ok

    push af
    ld hl, msgdebug_disconn
    call disptextz
    ld hl, S0_SR
    call W5100_READ_REG
    call disp_hex_byte
    call crlf
    pop af
    jp exit_close

.still_ok:
    ; Receive up to 255 bytes in a single batch (one SCMD_RECV for all)
    ld hl, recv_batch
    ld bc, 255
    call NET_RECV       ; BC = actual bytes received

    ld a, b
    or c
    jp z, recv_done

    ; Enter batch mode: suppress cursor interrupt, skip per-char cursor management.
    ; ROMDIS is NOT held here — SW1 calls it only around the 8-pixel write so that
    ; firmware interrupt hooks (M4 ROM) can run safely between characters.
    ; Do NOT call ToggleCursor here — it sets B=8 internally, corrupting BC.
    ld a, #C9
    ld (JChangeCursor), a   ; suppress cursor interrupt (prevents ToggleCursor→ROMDIS during batch)
    xor a
    ld (CursorOn), a
    ld (CursorCount), a
    ld a, 1
    ld (BatchMode), a

    ; DE = byte count, HL = start of batch (BC still has count from NET_RECV)
    ld d, b
    ld e, c
    ld hl, recv_batch

.batch_loop:
    ld a, d
    or e
    jp z, .batch_cleanup

    ld c, (hl)          ; C = current byte
    inc hl              ; advance batch pointer now (before push)
    dec de              ; decrement remaining count

    ; Check IAC state: 0=normal, 1=got IAC, 2=got IAC+cmd
    ld a, (telnet_iac_state)
    or a
    jr nz, .handle_iac  ; rare: inside an IAC sequence

    ; State 0: normal data — check for IAC byte (0xFF)
    ld a, c
    cp CMD
    jr z, .got_iac      ; rare

    ; Normal character — call ToScreen directly (saves ~125 T vs PrintChar).
    ; ToScreen/ScreenWrite handle all control chars; both preserve all registers.
    call ToScreen       ; A = character (set by ld a, c above, unchanged by cp/jr)
    jp .batch_loop

.got_iac:
    ld a, 1
    ld (telnet_iac_state), a
    jp .batch_loop

.handle_iac:
    cp 1
    jr nz, .iac_2

    ; State 1: save command byte, enter state 2
    ld a, c
    ld (telnet_iac_cmd), a
    ld a, 2
    ld (telnet_iac_state), a
    jp .batch_loop

.iac_2:
    ; State 2: option byte — save batch state, build and send response
    push hl             ; save batch pointer
    push de             ; save batch count

    ld a, (telnet_iac_cmd)
    ld b, a             ; B = cmd, C = option (already set)

    ld a, c
    cp 1                ; ECHO option?
    jr nz, .not_echo

    ld a, b
    cp 0xFB             ; WILL ECHO?
    jr nz, .chk_wont_echo

    xor a
    ld (local_echo_enabled), a
    ld hl, telnet_response
    ld (hl), 0xFF
    inc hl
    ld (hl), 0xFD       ; DO
    inc hl
    ld (hl), 1
    jr .send_resp

.chk_wont_echo:
    cp 0xFC             ; WONT ECHO?
    jr nz, .not_echo

    ld a, 1
    ld (local_echo_enabled), a
    ld hl, telnet_response
    ld (hl), 0xFF
    inc hl
    ld (hl), 0xFE       ; DONT
    inc hl
    ld (hl), 1
    jr .send_resp

.not_echo:
    ld a, b
    cp 0xFD             ; DO?
    jr z, .rsp_wont
    cp 0xFB             ; WILL?
    jr z, .rsp_dont
    jr .rst_state

.rsp_wont:
    ld hl, telnet_response
    ld (hl), 0xFF
    inc hl
    ld (hl), 0xFC       ; WONT
    inc hl
    ld (hl), c
    jr .send_resp

.rsp_dont:
    ld hl, telnet_response
    ld (hl), 0xFF
    inc hl
    ld (hl), 0xFE       ; DONT
    inc hl
    ld (hl), c

.send_resp:
    ld hl, telnet_response
    ld bc, 3
    call NET_SEND

.rst_state:
    ld hl, telnet_iac_state
    ld (hl), 0

    pop de              ; restore batch count
    pop hl              ; restore batch pointer
    jp .batch_loop

.batch_cleanup:
    xor a
    ld (BatchMode), a
    ld (JChangeCursor), a   ; re-enable cursor interrupt

recv_done:
    pop hl
    pop de
    pop bc
    pop af
    ret

; Display text routines
disptext:
    xor a
    cp c
    jr nz, not_dispend
    cp b
    ret z
not_dispend:
    ld a, (hl)
    push bc
    call printchar
    pop bc
    inc hl
    dec bc
    jr disptext

disptextz:
    ld a, (hl)
    or a
    ret z
    call PRINTCHAR
    inc hl
    jr disptextz

drawline:
    push af
    push bc
    ld a, 196
    call PrintChar80Times
    pop bc
    pop af
    ret

PrintChar80Times:
    ld b, 80

PrintLoop:
    push bc
    call PrintChar
    pop bc
    djnz PrintLoop
    ret

socket_error:
    call crlf
    ld hl, msgsocket_error
    call disptextz

    ; Flush keyboard buffer
.flush_sockerr_kb:
    call KM_READ_CHAR
    jr c, .flush_sockerr_kb

    jp loop_ip

connect_error:
    call crlf
    ld hl, msgconnect_error
    call disptextz

    ; Read socket status to see why it failed
    ld hl, msgdebug_socket_status
    call disptextz
    ld hl, S0_SR
    call W5100_READ_REG
    push af
    call disp_hex_byte
    call crlf
    pop af

    ; Read socket interrupt register
    ld hl, msgdebug_socket_ir
    call disptextz
    ld hl, S0_IR
    call W5100_READ_REG
    call disp_hex_byte
    call crlf

    ; Read and show gateway IP
    ld hl, msgdebug_gateway
    call disptextz
    ld hl, N_GAR0
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_GAR1
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_GAR2
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_GAR3
    call W5100_READ_REG
    call disp_dec
    call crlf

    ; Read and show subnet mask
    ld hl, msgdebug_subnet
    call disptextz
    ld hl, N_SUBR0
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_SUBR1
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_SUBR2
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_SUBR3
    call W5100_READ_REG
    call disp_dec
    call crlf

    ; Read and show our IP
    ld hl, msgdebug_ourip
    call disptextz
    ld hl, N_SIPR0
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_SIPR1
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_SIPR2
    call W5100_READ_REG
    call disp_dec
    ld a, '.'
    call printchar
    ld hl, N_SIPR3
    call W5100_READ_REG
    call disp_dec
    call crlf

    ; Flush keyboard buffer
.flush_connerr_kb:
    call KM_READ_CHAR
    jr c, .flush_connerr_kb

    jp loop_ip

disp_error:
    ld hl, msgerror
    jp disptextz

exit_error:
    call crlf
    call disp_error

    ; Flush keyboard buffer
.flush_error_kb:
    call KM_READ_CHAR
    jr c, .flush_error_kb

    jp loop_ip
    ret

exit_close:
    call crlf

    ld hl, msgclosing
    call disptextz

    call NET_CLOSE

    ; Flush keyboard buffer to clear any stray characters (ESC, control chars)
    ; that accumulated during the telnet session
.flush_exit_kb:
    call KM_READ_CHAR        ; Read without waiting
    jr c, .flush_exit_kb     ; Keep flushing while chars available

    jp loop_ip
    ret

Check_n4c:
    ; Check if W5100S is present by reading mode register
    ld hl, N_MR         ; N_MR = 0x0000 (register address, not port!)
    call W5100_READ_REG
    cp 3                ; Should return 3 if initialized
    jr z, found_n4c

    ld hl, msgno_n4c
    call disptextz
    ret

found_n4c:
    ld hl, msgfound_n4c
    call disptextz
    ret

; Messages
msgconnect:     db 10,13,"Connected.",10,13,0
msgserverip:    db 10,13,"Input server name or IP (:PORT or default to 23):",10,13,0
msgno_n4c:      db "No Net4CPC found, check connection.",10,13,0
msgfound_n4c:   db "Net4CPC W5100S detected",10,13,0
msgtest:        db "N4CEWENTERM 2026 v1.0 - Based on Ewenterm (1991) and M4EWENTERM (2023)",10,13,0
msgclosing:     db 10,13,"Connection closed.",10,13,0
msgerror:       db 10,13,"ERROR: Network error.",10,13,0
msgconnecting:  db 10,13, "Connecting to IP ",0
msgport:        db  " port ",0
msgdebug_socket: db 10,13,"[DEBUG] Creating TCP socket...",0
msgdebug_socket_ok: db " OK",10,13,0
msgdebug_connect: db "[DEBUG] Connecting...",10,13,0
msgdebug_port_loaded: db "[DEBUG] Port loaded from memory: 0x",0
msgsocket_error: db "ERROR: Failed to create socket",10,13,0
msgconnect_error: db "ERROR: Connection failed",10,13,0
msgdebug_socket_status: db "[DEBUG] Socket status register: 0x",0
msgdebug_socket_ir: db "[DEBUG] Socket interrupt register: 0x",0
msgdebug_gateway: db "[DEBUG] Gateway register: ",0
msgdebug_subnet: db "[DEBUG] Subnet mask: ",0
msgdebug_ourip: db "[DEBUG] Our IP: ",0
msgdebug_dest_ip: db "[DEBUG] W5100S Dest IP: ",0
msgdebug_dest_port: db "[DEBUG] W5100S Dest Port: ",0
msgready: db "Ready. ESC to disconnect, TAB to pause.",10,13,0
msgdebug_disconn: db "[DEBUG] Disconnect detected, socket status: 0x",0
msgdebug_keypress: db "[DEBUG] Key pressed: 0x",0
msgdebug_sent: db "[DEBUG] Send: ",0
msgdebug_rxsize: db "[DEBUG] RX buffer has ",0

; Data buffers
ip_addr:        db 127,0,0,1    ; Default localhost (for testing)
port:           dw 23           ; Port 23 (default telnet port)
sendtext:       ds 255
recvbuf:        ds 2048
recv_batch:     ds 255          ; batch receive buffer (255 bytes per mainloop tick)
BatchMode:      db 0            ; 1 = batch mode active (ROMDIS held, JChangeCursor suppressed)

; Telnet state machine for IAC sequence handling
; 0 = normal data, 1 = got IAC (0xFF), 2 = got IAC+command
telnet_iac_state:   db 0
telnet_iac_cmd:     db 0        ; Stores the IAC command byte
telnet_resp_opt:    db 0        ; Option code for response
telnet_response:    ds 3        ; Buffer for IAC response
local_echo_enabled: db 1        ; 1 = local echo on, 0 = off (server echoes)

; Compatibility stubs for negotiate.s (which expects M4 interface)
; recv - receive data (simplified stub)
recv:
    push hl
    push de

    ; BC has requested length
    ld hl, recvbuf
    call NET_RECV

    ; BC now has actual length received
    ; Copy to IY+6 for negotiate.s
    push iy
    pop hl
    ld de, 6
    add hl, de
    ld de, recvbuf
    ; Copy first 2 bytes for telnet negotiation
    ld a, (de)
    ld (hl), a
    inc de
    inc hl
    ld a, (de)
    ld (hl), a

    xor a           ; Return 0 (success)
    pop de
    pop hl
    ret

; sendcmd - send telnet command buffer (compatibility stub for negotiate.s)
; Entry: HL = ignored (kept for call-site compatibility).
;
; FIX: The negotiate.s code builds packets as:
;   sendsize+0 : length low byte
;   sendsize+1 : length high byte (always 0)
;   sendsize+2 : first data byte
;   sendsize+3 : second data byte  ... etc.
;
; The old stub passed HL=cmdsend to NET_SEND, which is a *separate* 16-byte
; buffer — only ever had a stale offset byte written into byte 0 and was
; otherwise uninitialised. The actual telnet command bytes live at sendsize+2.
;
; sendcmd now reads the length from sendsize and sends from sendsize+2.
sendcmd:
    ld bc, (sendsize)   ; BC = byte count to send
    ld hl, sendsize+2   ; HL = first byte of command data
    call NET_SEND
    ret

; Data areas for negotiate.s compatibility
cmdsend:        ds 16   ; kept so negotiate.s label references assemble; not used for sends
sendsize:       dw 0

; dispdec - display decimal (stub for negotiate.s)
dispdec:
    ; HL points to value
    ld a, (hl)
    ; Just print it as hex for now (simple stub)
    call printchar
    ret
