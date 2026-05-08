; W5100S Network Interface for Net4CPC
; Low-level socket routines for Amstrad CPC
; Based on KCNet W5100-12.INC and N4C-W51.INC

; W5100S I/O addresses (Net4CPC)
W51MR       equ 0xFD20      ; Mode register
W51HAD      equ 0xFD21      ; High address
W51LAD      equ 0xFD22      ; Low address
W51DAT      equ 0xFD23      ; Data

; W5100S Common Registers
N_MR        equ 0x0000      ; Mode register
N_RTR0      equ 0x0017      ; Retry time register (2 bytes)
N_RTR1      equ 0x0018
N_RCR       equ 0x0019      ; Retry count register
N_GAR0      equ 0x0001      ; Gateway address
N_GAR1      equ 0x0002
N_GAR2      equ 0x0003
N_GAR3      equ 0x0004
N_SUBR0     equ 0x0005      ; Subnet mask
N_SUBR1     equ 0x0006
N_SUBR2     equ 0x0007
N_SUBR3     equ 0x0008
N_SHAR0     equ 0x0009      ; Source hardware address (MAC)
N_SIPR0     equ 0x000F      ; Source IP address
N_SIPR1     equ 0x0010
N_SIPR2     equ 0x0011
N_SIPR3     equ 0x0012

; Socket 0 Registers (we'll use socket 0 for telnet)
S0_MR       equ 0x0400      ; Socket 0 mode register
S0_CR       equ 0x0401      ; Socket 0 command register
S0_IR       equ 0x0402      ; Socket 0 interrupt register
S0_SR       equ 0x0403      ; Socket 0 status register
S0_PORT0    equ 0x0404      ; Socket 0 source port
S0_DHAR0    equ 0x0406      ; Socket 0 dest hardware addr
S0_DIPR0    equ 0x040C      ; Socket 0 dest IP address
S0_DIPR1    equ 0x040D
S0_DIPR2    equ 0x040E
S0_DIPR3    equ 0x040F
S0_DPORT0   equ 0x0410      ; Socket 0 dest port
S0_DPORT1   equ 0x0411
S0_TX_FSR0  equ 0x0420      ; Socket 0 TX free size
S0_TX_RD0   equ 0x0422      ; Socket 0 TX read pointer
S0_TX_WR0   equ 0x0424      ; Socket 0 TX write pointer
S0_TX_WR1   equ 0x0425
S0_RX_RSR0  equ 0x0426      ; Socket 0 RX received size
S0_RX_RSR1  equ 0x0427
S0_RX_RD0   equ 0x0428      ; Socket 0 RX read pointer
S0_RX_RD1   equ 0x0429

; Socket commands
SCMD_OPEN      equ 0x01
SCMD_LISTEN    equ 0x02
SCMD_CONNECT   equ 0x04
SCMD_DISCON    equ 0x08
SCMD_CLOSE     equ 0x10
SCMD_SEND      equ 0x20
SCMD_RECV      equ 0x40

; Socket status values
SSTAT_CLOSED       equ 0x00
SSTAT_INIT         equ 0x13
SSTAT_LISTEN       equ 0x14
SSTAT_ESTABLISHED  equ 0x17
SSTAT_CLOSE_WAIT   equ 0x1C
SSTAT_UDP          equ 0x22
SSTAT_IPRAW        equ 0x32
SSTAT_MACRAW       equ 0x42
SSTAT_PPPOE        equ 0x5F
SSTAT_SYNSENT      equ 0x15
SSTAT_SYNRECV      equ 0x16
SSTAT_FIN_WAIT     equ 0x18
SSTAT_TIME_WAIT    equ 0x1B

; Socket modes
SMODE_TCP      equ 0x01
SMODE_UDP      equ 0x02
SK_STREAM      equ 1       ; TCP mode (for compatibility)
SK_DGRAM       equ 2       ; UDP mode (for compatibility)

; KCNet constants
N_XTIME        equ 6554    ; Max value (ms) of time-service
COMP_SCHEME    equ 0xC0    ; DNS compression scheme

; TX/RX Buffer base addresses
S0_TX_BASE     equ 0x4000
S0_RX_BASE     equ 0x6000
S0_TX_MASK     equ 0x07FF   ; 2KB buffer
S0_RX_MASK     equ 0x07FF   ; 2KB buffer

;-------------------------------------------------------
; W5100_WRITE_REG - Write a byte to W5100S register
; Entry: HL = register address, A = byte to write
; Exit:  None
; Uses:  BC
;-------------------------------------------------------
W5100_WRITE_REG:
    push bc
    ld bc, W51HAD
    out (c), h          ; High address
    inc c
    out (c), l          ; Low address
    inc c
    out (c), a          ; Data
    pop bc
    ret

;-------------------------------------------------------
; W5100_READ_REG - Read a byte from W5100S register
; Entry: HL = register address
; Exit:  A = byte read
; Uses:  BC
;-------------------------------------------------------
W5100_READ_REG:
    push bc
    ld bc, W51HAD
    out (c), h          ; High address
    inc c
    out (c), l          ; Low address
    inc c
    in a, (c)           ; Data
    pop bc
    ret

;-------------------------------------------------------
; W5100_WRITE_BUF - Write buffer to W5100S
; Entry: HL = host buffer address
;        DE = W5100S address
;        BC = length
; Exit:  HL = HL + BC
; Uses:  All
;-------------------------------------------------------
W5100_WRITE_BUF:
    push af
    push de
    push bc

    ld bc, W51HAD
    ld a, d
    out (c), a          ; Write high address
    inc c
    ld a, e
    out (c), a          ; Write low address
    inc c               ; BC now points to W51DAT

    pop de              ; Length to DE

.wbuf_loop:
    ld a, d
    or e
    jr z, .wbuf_done

    ld a, (hl)
    out (c), a          ; Write data byte
    inc hl
    dec de
    jr .wbuf_loop

.wbuf_done:
    pop de
    pop af
    ret

;-------------------------------------------------------
; W5100_READ_BUF - Read buffer from W5100S
; Entry: HL = host buffer address
;        DE = W5100S address
;        BC = length
; Exit:  HL = HL + BC
; Uses:  All
;-------------------------------------------------------
W5100_READ_BUF:
    push af
    push de
    push bc             ; Save length

    ld bc, W51HAD
    ld a, d
    out (c), a          ; Write high address
    inc c
    ld a, e
    out (c), a          ; Write low address
    inc c               ; BC now points to W51DAT

    pop de              ; Get length into DE

.rbuf_loop:
    ld a, d
    or e
    jr z, .rbuf_done

    in a, (c)           ; Read data byte
    ld (hl), a
    inc hl
    dec de
    jr .rbuf_loop

.rbuf_done:
    pop de
    pop af
    ret

;-------------------------------------------------------
; NET_SOCKET - Initialize socket (like M4 C_NETSOCKET)
; Entry: A = socket number (0-3), B = protocol (1=TCP)
; Exit:  Carry clear if OK, set if error
;-------------------------------------------------------
NET_SOCKET:
    push hl
    push bc

    ; Set longer ARP retry timeout (10000 = 1 second)
    ld hl, N_RTR0
    ld a, 0x27          ; High byte of 10000
    call W5100_WRITE_REG
    inc hl
    ld a, 0x10          ; Low byte of 10000
    call W5100_WRITE_REG

    ; Set retry count to 10
    ld hl, N_RCR
    ld a, 10
    call W5100_WRITE_REG

    ; Set socket mode to TCP
    ld hl, S0_MR
    ld a, SMODE_TCP
    call W5100_WRITE_REG

    ; Set source port (default 5000)
    ld hl, S0_PORT0
    ld a, 0x13          ; High byte of 5000
    call W5100_WRITE_REG
    inc hl
    ld a, 0x88          ; Low byte of 5000
    call W5100_WRITE_REG

    ; Send OPEN command
    ld hl, S0_CR
    ld a, SCMD_OPEN
    call W5100_WRITE_REG

    ; Wait for command completion
    call WAIT_CMD_DONE

    ; Check socket status
    ld hl, S0_SR
    call W5100_READ_REG
    cp SSTAT_INIT
    jr z, .socket_ok

    scf                 ; Set carry for error
    jr .socket_exit

.socket_ok:
    or a                ; Clear carry for success

.socket_exit:
    pop bc
    pop hl
    ret

;-------------------------------------------------------
; NET_CONNECT - Connect to host (like M4 C_NETCONNECT)
; Entry: HL = pointer to IP address (4 bytes)
;        BC = port number (network order)
; Exit:  Carry clear if OK, set if error
;-------------------------------------------------------
NET_CONNECT:
    push hl             ; Save IP address pointer
    push de
    push bc

    ; Clear socket interrupt register first
    push hl             ; Save ip_addr pointer again
    ld hl, S0_IR
    ld a, 0xFF
    call W5100_WRITE_REG
    pop hl              ; Restore ip_addr pointer

    ; Write destination IP
    ld de, S0_DIPR0
    push bc
    ld bc, 4
    call W5100_WRITE_BUF
    pop bc

    ; Write destination port
    ld hl, S0_DPORT0
    ld a, b
    call W5100_WRITE_REG
    inc hl
    ld a, c
    call W5100_WRITE_REG

    ; Send CONNECT command
    ld hl, S0_CR
    ld a, SCMD_CONNECT
    call W5100_WRITE_REG

    ; Wait for CONNECT command to complete
    call WAIT_CMD_DONE

    ; Wait for connection (with timeout)
    ld de, 5000         ; Longer timeout counter
.wait_connect:
    ld hl, S0_SR
    call W5100_READ_REG
    cp SSTAT_ESTABLISHED
    jr z, .connect_ok

    ; Check for error states
    cp 0x00             ; SOCK_CLOSED = failed
    jr z, .connect_timeout
    cp 0x1C             ; SOCK_LAST_ACK = closing
    jr z, .connect_timeout

    ; Small delay
    push de
    ld b, 255
.delay:
    djnz .delay
    pop de

    dec de
    ld a, d
    or e
    jr nz, .wait_connect

.connect_timeout:

    ; Timeout
    scf
    jr .connect_exit

.connect_ok:
    or a                ; Clear carry

.connect_exit:
    pop bc
    pop de
    pop hl
    ret

;-------------------------------------------------------
; NET_SEND - Send data (like M4 C_NETSEND)
; Entry: HL = buffer address
;        BC = length
; Exit:  Carry clear if OK, set if error
; Fix: Rewrote with balanced stack. Old version had a
;      spurious push de at entry that was never cleanly
;      popped, corrupting the return address on ret.
;-------------------------------------------------------
NET_SEND:
    push hl             ; [1] save data buffer pointer
    push bc             ; [2] save length

    ; Read current TX write pointer into DE
    ld hl, S0_TX_WR0
    call W5100_READ_REG
    ld d, a
    ld hl, S0_TX_WR1
    call W5100_READ_REG
    ld e, a             ; DE = current TX write pointer

    ; Calculate physical W5100S TX buffer address:
    ;   offset = write_ptr AND S0_TX_MASK  (keep low 11 bits)
    ;   physical = S0_TX_BASE + offset
    ld a, e
    and S0_TX_MASK & 0xFF
    ld l, a
    ld a, d
    and S0_TX_MASK >> 8
    ld h, a             ; HL = masked offset (0x0000 - 0x07FF)
    ld de, S0_TX_BASE
    add hl, de          ; HL = physical W5100S address
    ex de, hl           ; DE = physical address (for W5100_WRITE_BUF)

    ; Restore data pointer and length for the write
    pop bc              ; [2] BC = length
    pop hl              ; [1] HL = data buffer pointer

    push bc             ; [3] save length for pointer update below
    call W5100_WRITE_BUF    ; write BC bytes from (HL) to W5100S at DE

    ; Update TX write pointer: new_ptr = old_ptr + length
    pop bc              ; [3] BC = length

    ld hl, S0_TX_WR0
    call W5100_READ_REG
    ld d, a
    ld hl, S0_TX_WR1
    call W5100_READ_REG
    ld e, a             ; DE = current write pointer (re-read for safety)
    ex de, hl           ; HL = write pointer
    add hl, bc          ; HL = new write pointer
    ex de, hl           ; DE = new write pointer

    ld hl, S0_TX_WR0
    ld a, d
    call W5100_WRITE_REG
    ld hl, S0_TX_WR1
    ld a, e
    call W5100_WRITE_REG

    ; Issue SEND command and wait for completion
    ld hl, S0_CR
    ld a, SCMD_SEND
    call W5100_WRITE_REG

    call WAIT_CMD_DONE

    or a                ; Clear carry = success
    ret

;-------------------------------------------------------
; NET_RECV - Receive data (like M4 C_NETRECV)
; Entry: HL = buffer address
;        BC = max length
; Exit:  BC = actual bytes received
;        Carry clear if OK
; Reads up to BC bytes in a single batch; issues SCMD_RECV
; only once at the end to minimise W5100S I/O overhead.
;-------------------------------------------------------
NET_RECV:
    push hl             ; [A] save buffer pointer
    push bc             ; [B] save requested max

    ; Check how much data is actually available
    ld hl, S0_RX_RSR0
    call W5100_READ_REG
    ld d, a
    ld hl, S0_RX_RSR1
    call W5100_READ_REG
    ld e, a             ; DE = bytes available

    ld a, d
    or e
    jr z, .recv_no_data

    ; actual = min(requested, available)
    pop bc              ; [B] BC = requested
    ld a, b
    cp d
    jr c, .bc_is_min    ; B < D → BC < DE
    jr nz, .de_is_min   ; B > D → DE < BC
    ld a, c
    cp e
    jr c, .bc_is_min    ; B==D, C < E → BC < DE
.de_is_min:
    ld b, d
    ld c, e             ; BC = available (smaller)
.bc_is_min:
    ; BC = actual bytes to read

    push bc             ; [B] save actual count

    ; Get RX read pointer
    ld hl, S0_RX_RD0
    call W5100_READ_REG
    ld d, a
    ld hl, S0_RX_RD1
    call W5100_READ_REG
    ld e, a             ; DE = RX read pointer

    pop bc              ; [B] BC = actual count
    pop hl              ; [A] HL = buffer pointer

    push bc             ; [A] save actual count for return value

    ; Read BC bytes from the W5100S RX ring buffer
.recv_byte_loop:
    ld a, b
    or c
    jr z, .recv_loop_done

    push bc             ; save remaining count
    push hl             ; save buffer pointer
    push de             ; save RD pointer

    ; physical = (DE & 0x07FF) + S0_RX_BASE
    ld a, e
    and 0xFF
    ld l, a
    ld a, d
    and 0x07
    ld h, a
    ld de, S0_RX_BASE
    add hl, de          ; HL = physical W5100S address

    call W5100_READ_REG ; A = data byte (HL unchanged)

    pop de              ; restore RD pointer
    pop hl              ; restore buffer pointer
    pop bc              ; restore remaining count

    ld (hl), a          ; store byte
    inc hl              ; advance buffer
    inc de              ; advance RD pointer (natural 16-bit wrap)
    dec bc
    jr .recv_byte_loop

.recv_loop_done:
    ; Write updated RD pointer back once
    ld hl, S0_RX_RD0
    ld a, d
    call W5100_WRITE_REG
    ld hl, S0_RX_RD1
    ld a, e
    call W5100_WRITE_REG

    ; Issue RECV command once for the entire batch
    ld hl, S0_CR
    ld a, SCMD_RECV
    call W5100_WRITE_REG
    call WAIT_CMD_DONE

    pop bc              ; [A] return actual count
    or a                ; clear carry
    ret

.recv_no_data:
    pop bc              ; [B] discard requested
    pop hl              ; [A] discard buffer ptr
    ld bc, 0
    or a
    ret

;-------------------------------------------------------
; NET_CLOSE - Close socket (like M4 C_NETCLOSE)
; Entry: None
; Exit:  None
;-------------------------------------------------------
NET_CLOSE:
    push hl
    push af

    ; Send DISCONNECT command
    ld hl, S0_CR
    ld a, SCMD_DISCON
    call W5100_WRITE_REG

    call WAIT_CMD_DONE

    ; Wait a bit
    ld b, 255
.delay1:
    djnz .delay1

    ; Send CLOSE command
    ld hl, S0_CR
    ld a, SCMD_CLOSE
    call W5100_WRITE_REG

    call WAIT_CMD_DONE

    pop af
    pop hl
    ret

;-------------------------------------------------------
; WAIT_CMD_DONE - Wait for socket command to complete
; Entry: None
; Exit:  None
;-------------------------------------------------------
WAIT_CMD_DONE:
    push hl
    push af

.wait_loop:
    ld hl, S0_CR
    call W5100_READ_REG
    or a
    jr nz, .wait_loop

    pop af
    pop hl
    ret

;-------------------------------------------------------
; CHECK_CONNECTION - Check if still connected
; Entry: None
; Exit:  Carry clear if connected, set if disconnected
;-------------------------------------------------------
CHECK_CONNECTION:
    push hl

    ld hl, S0_SR
    call W5100_READ_REG
    cp SSTAT_ESTABLISHED
    jr z, .still_connected

    cp SSTAT_CLOSE_WAIT
    jr z, .disconnected

    ; Any other state considered disconnected
.disconnected:
    scf
    jr .check_exit

.still_connected:
    or a

.check_exit:
    pop hl
    ret

;=======================================================
; KCNet-compatible API for DNS client
;=======================================================

;-------------------------------------------------------
; SOCKET - Create a socket (KCNet API)
; Entry: A = socket number (0-3), 0xFF = auto-allocate
;        D = mode (SK_STREAM=1 or SK_DGRAM=2)
;        E = flags (unused)
; Exit:  A = socket number if OK
;        Carry clear if OK, set if error
;-------------------------------------------------------
SOCKET:
    push hl
    push bc
    push de

    ; For simplicity, use socket 1 for UDP (DNS)
    ; Socket 0 is reserved for TCP (telnet)
    ld a, 1

    ; Ensure socket is closed: issue CLOSE, wait for command, then wait for
    ; S1_SR to actually reach SSTAT_CLOSED (0x00), then clear S1_IR so no
    ; stale interrupt bits from a previous session confuse the new open.
    ld hl, S1_CR
    ld a, SCMD_CLOSE
    call W5100_WRITE_REG
    call WAIT_CMD_DONE_S1

    ld bc, 2000
.wait_s1_closed:
    ld hl, S1_SR
    call W5100_READ_REG
    or a
    jr z, .s1_is_closed
    dec bc
    ld a, b
    or c
    jr nz, .wait_s1_closed
.s1_is_closed:
    ld hl, S1_IR
    ld a, 0xFF
    call W5100_WRITE_REG

    ; Set socket mode
    ld hl, S1_MR
    ld a, d
    cp SK_DGRAM
    jr z, .udp_mode
    ld a, SMODE_TCP
    jr .set_mode
.udp_mode:
    ld a, SMODE_UDP
.set_mode:
    call W5100_WRITE_REG

    ; Set source port for UDP (use dynamic port)
    push de
    call N_DPRT         ; Get dynamic port in HL (network order)
    ld d, h
    ld e, l
    ld hl, S1_PORT0
    ld a, d
    call W5100_WRITE_REG
    inc hl
    ld a, e
    call W5100_WRITE_REG
    pop de

    ; Open the socket
    ld hl, S1_CR
    ld a, SCMD_OPEN
    call W5100_WRITE_REG

    call WAIT_CMD_DONE_S1

    ; Check status
    ld hl, S1_SR
    call W5100_READ_REG
    cp SSTAT_INIT
    jr z, .socket_ok
    cp SSTAT_UDP
    jr z, .socket_ok

    scf
    jr .socket_exit

.socket_ok:
    ld a, 1         ; Return socket number
    or a            ; Clear carry

.socket_exit:
    pop de
    pop bc
    pop hl
    ret

;-------------------------------------------------------
; CONNECT - Connect/bind socket (KCNet API)
; Entry: A = socket number
; Exit:  Carry clear if OK, set if error
;-------------------------------------------------------
CONNECT:
    ; For UDP, just return success
    ; Binding happens automatically
    or a
    ret

;-------------------------------------------------------
; CLOSE - Close socket (KCNet API)
; Entry: A = socket number
; Exit:  None
;-------------------------------------------------------
CLOSE:
    push hl
    push af

    cp 1
    jr nz, .close_s0

    ; Close socket 1 (UDP)
    ld hl, S1_CR
    ld a, SCMD_CLOSE
    call W5100_WRITE_REG
    call WAIT_CMD_DONE_S1
    ld hl, S1_IR
    ld a, 0xFF
    call W5100_WRITE_REG
    jr .close_exit

.close_s0:
    ; Close socket 0 (TCP)
    call NET_CLOSE

.close_exit:
    pop af
    pop hl
    ret

;-------------------------------------------------------
; SENDTO - Send UDP datagram (KCNet API)
; Entry: A = socket number
;        HL = data buffer
;        BC = data length
;        DE = peer data (4 byte IP + 2 byte port)
; Exit:  Carry clear if OK, set if error
;-------------------------------------------------------
SENDTO:
    push hl
    push de
    push bc
    push af

    ; Save peer data pointer for later use
    ld (sendto_peer_ptr), de

    ; Set destination IP (4 bytes) - write byte by byte
    push hl
    push bc
    ld hl, (sendto_peer_ptr)
    ; Byte 0
    ld a, (hl)
    push hl
    ld hl, S1_DIPR0
    call W5100_WRITE_REG
    pop hl
    inc hl
    ; Byte 1
    ld a, (hl)
    push hl
    ld hl, S1_DIPR0 + 1
    call W5100_WRITE_REG
    pop hl
    inc hl
    ; Byte 2
    ld a, (hl)
    push hl
    ld hl, S1_DIPR0 + 2
    call W5100_WRITE_REG
    pop hl
    inc hl
    ; Byte 3
    ld a, (hl)
    push hl
    ld hl, S1_DIPR0 + 3
    call W5100_WRITE_REG
    pop hl
    inc hl
    ; HL now at peer_ptr + 4 (port)
    ; Byte 4 (port MSB)
    ld a, (hl)
    push hl
    ld hl, S1_DPORT0
    call W5100_WRITE_REG
    pop hl
    inc hl
    ; Byte 5 (port LSB)
    ld a, (hl)
    ld hl, S1_DPORT0 + 1
    call W5100_WRITE_REG
    pop bc
    pop hl

    ; Get data buffer and length
    pop af          ; Socket number (ignored)
    pop bc          ; Length
    pop de          ; Peer data (no longer needed)
    pop hl          ; Data buffer

    push hl
    push bc

    ; Check socket status first
    ld hl, S1_SR
    call W5100_READ_REG
    cp SSTAT_UDP
    jp nz, .sendto_error    ; Socket not in UDP state

    ; Wait for TX buffer to have enough free space
    ld hl, 1000             ; Timeout counter (reduced for faster failure)
.wait_tx_free:
    push hl                 ; Save timeout counter
    push bc
    ld hl, S1_TX_FSR0
    call W5100_READ_REG
    ld h, a
    ld hl, S1_TX_FSR0 + 1
    call W5100_READ_REG
    ld l, a
    ; HL now has free space, BC on stack has data length
    pop bc
    push bc
    ; Compare: is HL >= BC?
    or a
    sbc hl, bc
    pop bc
    pop hl                  ; Restore timeout counter
    jp nc, .tx_ready        ; If no carry, HL >= BC, ready

    ; Decrement timeout counter
    dec hl
    ld a, h
    or l
    jr nz, .wait_tx_free    ; Continue if not zero
    ; Timeout!
    jp .sendto_error

.tx_ready:
    ; Write data to TX buffer
    ld hl, S1_TX_WR0
    call W5100_READ_REG
    ld d, a
    ld hl, S1_TX_WR0 + 1
    call W5100_READ_REG
    ld e, a

    ; Calculate physical address
    push de
    ld a, e
    and S1_TX_MASK & 0xFF
    ld l, a
    ld a, d
    and S1_TX_MASK >> 8
    ld h, a
    ld de, S1_TX_BASE
    add hl, de
    ld d, h
    ld e, l
    pop hl

    ; Write data
    pop bc          ; Length
    pop hl          ; Data
    push hl
    push bc

    call W5100_WRITE_BUF

    ; Update TX write pointer
    pop bc
    ld hl, S1_TX_WR0
    call W5100_READ_REG
    ld d, a              ; D = MSB (ld h,a would be overwritten by next ld hl)
    ld hl, S1_TX_WR0 + 1
    call W5100_READ_REG
    ld e, a              ; E = LSB
    ex de, hl            ; HL = current TX write pointer
    add hl, bc

    push hl
    ld hl, S1_TX_WR0
    pop de
    ld a, d
    call W5100_WRITE_REG
    inc hl
    ld a, e
    call W5100_WRITE_REG

    ; Send command
    ld hl, S1_CR
    ld a, SCMD_SEND
    call W5100_WRITE_REG
    call WAIT_CMD_DONE_S1

    ; Wait for SENDOK or TIMEOUT interrupt
    push bc
    ld bc, 1000             ; Timeout counter (reduced)
.wait_send_ir:
    ld hl, S1_IR
    call W5100_READ_REG
    and 0x18                ; Check SENDOK (0x10) or TIMEOUT (0x08)
    jr nz, .got_interrupt

    ; Decrement timeout
    dec bc
    ld a, b
    or c
    jr nz, .wait_send_ir    ; Continue if not zero

    ; Timeout - no interrupt received
    pop bc
    pop hl
    scf
    ret

.got_interrupt:
    ; Clear the interrupt
    push af
    ld hl, S1_IR
    call W5100_WRITE_REG    ; Write back to clear
    pop af

    ; Check if it was SENDOK or TIMEOUT
    and 0x10                ; Check SENDOK bit
    pop bc
    jr nz, .send_ok

    ; TIMEOUT - return error
    pop hl
    scf
    ret

.sendto_error:
    ; Error during sendto (socket wrong state or TX timeout)
    pop bc
    pop hl
    scf
    ret

.send_ok:
    pop hl
    or a
    ret

;-------------------------------------------------------
; RECVFR - Receive UDP datagram (KCNet API)
; Entry: A = socket number
;        HL = data buffer
;        BC = max length
;        DE = peer info buffer (8 bytes: 4 IP + 2 port + 2 size)
; Exit:  BC = actual bytes received
;        Carry clear if OK, set if error
;-------------------------------------------------------
RECVFR:
    ; Stub - not used, using direct RX read instead
    scf
    ret

;-------------------------------------------------------
; SELECT - Check if data available (KCNet API)
; Entry: A = socket number
;        E = select type (SL_RECV=1)
; Exit:  Carry clear if data available, set if not
;-------------------------------------------------------
SL_RECV equ 1

SELECT:
    push hl
    push af
    push bc

    ; Check RX received size register (2 bytes, MSB first)
    ld hl, S1_RX_RSR0
    call W5100_READ_REG
    ld b, a             ; B = MSB
    ld hl, S1_RX_RSR0 + 1
    call W5100_READ_REG
    ld c, a             ; C = LSB

    ; If size > 0, data available
    ld a, b
    or c
    jr z, .no_data

    pop bc

    pop af
    pop hl
    or a            ; Clear carry
    ret

.no_data:
    pop bc
    pop af
    pop hl
    scf
    ret

;-------------------------------------------------------
; N_TIME - Read timer value (KCNet API)
; Entry: None
; Exit:  HL = timer value in milliseconds (0-59999)
; Uses CPC firmware frame flyback counter at 0xAC7E (16-bit, increments 50Hz)
;-------------------------------------------------------
N_TIME:
    push af
    push bc
    push de

    ; Read CPC frame counter (0xB5CB, 16-bit, 50Hz, standard firmware ISR)
    ld hl, (0xB5CB)

    ; Convert from 1/50 sec to milliseconds
    ; HL = HL * 20 (since 1000ms/50 = 20ms per frame)
    ; HL * 20 = HL * 16 + HL * 4
    ld d, h
    ld e, l             ; DE = HL
    add hl, hl          ; HL * 2
    add hl, hl          ; HL * 4
    ld b, h
    ld c, l             ; BC = HL * 4
    add hl, hl          ; HL * 8
    add hl, hl          ; HL * 16
    add hl, bc          ; HL * 16 + HL * 4 = HL * 20

    ; Keep only lower 16 bits (natural wrap at 65535)
    ; Since frame counter wraps at 65535, and *20 could overflow,
    ; we just use the result as-is

    pop de
    pop bc
    pop af
    ret

;-------------------------------------------------------
; N_WIPA - Write IP address to storage (KCNet API)
; Entry: A = IP number (N_DNSIP = 0)
;        HL = host address of IP (4 bytes)
; Exit:  HL = HL + 4
;-------------------------------------------------------
N_DNSIP equ 0

N_WIPA:
    push af
    push bc
    push de

    ; DNS IP stored at PPPoE dest hardware addr (0x0032)
    ld de, 0x0032
    ld bc, 4
    call W5100_WRITE_BUF

    pop de
    pop bc
    pop af
    ret

;-------------------------------------------------------
; N_RIPA - Read IP address from storage (KCNet API)
; Entry: A = IP number (N_DNSIP = 0)
;        HL = host address for IP (4 bytes)
; Exit:  HL = HL + 4
;-------------------------------------------------------
N_RIPA:
    push af
    push bc
    push de

    ; DNS IP stored at PPPoE dest hardware addr (0x0032)
    ld de, 0x0032
    ld bc, 4
    call W5100_READ_BUF

    pop de
    pop bc
    pop af
    ret

;-------------------------------------------------------
; N_DPRT - Get dynamic port number (KCNet API)
; Entry: None
; Exit:  HL = port number, H = MSB, L = LSB (for SOCKET to write directly)
; Uses a RAM counter to give each session a distinct source port.
; Cycles 0xC001-0xC0FF (49153-49407), wrapping at 0x00 back to 0xC001.
;-------------------------------------------------------
N_DPRT:
    push af
    push bc
    push de

    ld hl, dprt_seq
    ld a, (hl)
    inc a
    jr nz, .dprt_nowrap
    inc a               ; skip 0x00 to keep port visibly non-zero
.dprt_nowrap:
    ld (hl), a
    ld l, a             ; L = LSB (counter byte)
    ld h, 0xC0          ; H = MSB (0xC0 keeps port >= 49152)

    pop de
    pop bc
    pop af
    ret

;-------------------------------------------------------
; NTOHS - Network to host short (KCNet API)
; Entry: HL = pointer to 16-bit value in network order
; Exit:  HL = value in host order
; Note: Swaps bytes (network=big-endian, Z80=little-endian)
;-------------------------------------------------------
NTOHS:
    push af
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    pop af
    ret

;-------------------------------------------------------
; HTONS - Host to network short (KCNet API)
; Entry: HL = value in host order
; Exit:  HL = value in network order
;-------------------------------------------------------
HTONS:
    push af
    ld a, h
    ld h, l
    ld l, a
    pop af
    ret

;-------------------------------------------------------
; NTOHL - Network to host long (KCNet API)
; Entry: DE = pointer to 32-bit value in network order
;        HL = destination
; Exit:  HL = HL + 4
;-------------------------------------------------------
NTOHL:
    push af
    push bc

    ld a, (de)
    inc de
    ld b, a
    ld a, (de)
    inc de
    ld c, a

    ex de, hl
    ld (hl), c
    inc hl
    ld (hl), b
    inc hl

    ex de, hl
    ld a, (de)
    inc de
    ld b, a
    ld a, (de)
    inc de
    ld c, a

    ex de, hl
    ld (hl), c
    inc hl
    ld (hl), b
    inc hl

    ex de, hl

    pop bc
    pop af
    ret

;-------------------------------------------------------
; I_NTOA - Convert IP to dotted decimal string (KCNet API)
; Entry: HL = IP address (4 bytes, network order)
;        DE = string buffer
; Exit:  DE = points after string + 0
;-------------------------------------------------------
I_NTOA:
    push af
    push bc
    push hl

    ld b, 4

.ntoa_loop:
    ld a, (hl)
    push hl
    push bc
    call byte_to_dec
    pop bc
    pop hl

    inc hl
    dec b
    jr z, .ntoa_done

    ld a, '.'
    ld (de), a
    inc de
    jr .ntoa_loop

.ntoa_done:
    xor a
    ld (de), a
    inc de

    pop hl
    pop bc
    pop af
    ret

; Helper: convert byte to decimal string
byte_to_dec:
    push bc
    push hl

    ld l, a
    ld h, 0
    ld bc, 100
    call div16
    add a, '0'
    cp '0'
    jr z, .skip_100

    ld (de), a
    inc de

.skip_100:
    ld a, l
    ld bc, 10
    call div16
    add a, '0'
    cp '0'
    jr nz, .write_10
    ld a, (de)
    cp 0
    jr z, .skip_10

.write_10:
    add a, '0'
    ld (de), a
    inc de

.skip_10:
    ld a, l
    add a, '0'
    ld (de), a
    inc de

    pop hl
    pop bc
    ret

; Helper: 16-bit division
; HL / BC = A (quotient), HL = remainder
div16:
    push bc
    push de

    ld a, l
    ld de, 0

.div_loop:
    cp c
    jr c, .div_done
    sub c
    inc e
    jr .div_loop

.div_done:
    ld l, a
    ld a, e

    pop de
    pop bc
    ret

;-------------------------------------------------------
; Socket 1 Registers (for UDP/DNS)
;-------------------------------------------------------
S1_MR       equ 0x0500
S1_CR       equ 0x0501
S1_IR       equ 0x0502
S1_SR       equ 0x0503
S1_PORT0    equ 0x0504
S1_DHAR0    equ 0x0506
S1_DIPR0    equ 0x050C
S1_DPORT0   equ 0x0510
S1_TX_FSR0  equ 0x0520
S1_TX_RD0   equ 0x0522
S1_TX_WR0   equ 0x0524
S1_RX_RSR0  equ 0x0526
S1_RX_RD0   equ 0x0528

; Socket 1 TX/RX buffers
S1_TX_BASE  equ 0x4800
S1_RX_BASE  equ 0x6800
S1_TX_MASK  equ 0x07FF
S1_RX_MASK  equ 0x07FF

WAIT_CMD_DONE_S1:
    push hl
    push af
    push bc

    ld bc, 1000             ; Timeout counter (reduced)

.wait_loop:
    ld hl, S1_CR
    call W5100_READ_REG
    or a
    jr z, .cmd_done

    ; Decrement timeout
    dec bc
    ld a, b
    or c
    jr nz, .wait_loop       ; Continue if not zero

    ; Timeout - command never completed
    ; Continue anyway (might cause issues but better than hanging)

.cmd_done:
    pop bc
    pop af
    pop hl
    ret

;-------------------------------------------------------
; SENDTO variables
;-------------------------------------------------------
sendto_peer_ptr:    dw 0        ; Saved peer data pointer
dprt_seq:           db 0        ; N_DPRT source port counter (cycles 0x01-0xFF)
