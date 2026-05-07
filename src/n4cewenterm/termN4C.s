; Assembled with Rasm for Z80
;
; An ANSI Telnet client for the Amstrad CPC with Net4CPC
; Based on M4EWENTERM (https://github.com/fleen/m4ewenterm/) 2023
; which was based on Ewenterm (https://ewen.mcneill.gen.nz/programs/cpc/ewenterm/) 1991
; Adapted for Net4CPC 2026

true        equ 1
false       equ 0
on          equ true
off         equ false
screen_depth    equ 25

colour      equ true

    org #7000 ; Start assembling at #7000, Charset loaded at runtime

    nolist

; Constants and firmware routines

Characterset  equ #6800
HCharSet      equ #0068

top

;*** Keyboard
KM_READ_KEY             equ #BB1B
KM_WAIT_KEY             equ #BB18
KM_GET_EXPAND           equ #BB12
KM_TEST_KEY             equ #BB1E
KM_READ_CHAR            equ #BB09
KM_WAIT_CHAR            equ #BB06
KM_GET_TRANSLATE        equ #BB2A
KM_SET_TRANSLATE        equ #BB27

;*** Text Screen
TXT_OUTPUT              equ #BB5A
TXT_WR_CHAR             equ #BB5D
TXT_WIN_ENABLE          equ #BB66
TXT_GET_WINDOW          equ #BB69
TXT_SET_COLUMN          equ #BB6F
TXT_SET_ROW             equ #BB72
TXT_SET_CURSOR          equ #BB75
TXT_GET_CURSOR          equ #BB78
TXT_CUR_ON              equ #BB81
TXT_CUR_OFF             equ #BB84
TXT_GET_MATRIX          equ #BBA5

;*** Screen, General
SCR_SET_OFFSET          equ #BC05
SCR_SET_MODE            equ #BC0E
SCR_GET_MODE            equ #BC11
SCR_CLEAR               equ #BC14
SCR_SET_INK             equ #BC32
SCR_GET_INK             equ #BC35
SCR_HW_ROLL             equ #BC4D

;*** Machine pack
MC_WAIT_FLYBACK         equ #BD19
MC_PRINT_CHAR           equ #BD2B
MC_BUSY_PRINTER         equ #BD2E

;*** Cassette/Disc
CAS_OUT_OPEN            equ #BC8C
CAS_OUT_CLOSE           equ #BC8F
CAS_OUT_CHAR            equ #BC95

;*** Kernel - High
KL_U_ROM_DISABLE        equ #B903
KL_ROM_RESTORE          equ #B90C

;*** Kernal - Normal
KL_LOG_EXT              equ #BCD1
KL_FIND_COMMAND         equ #BCD4
KL_NEW_FRAME_FLY        equ #BCD7
KL_DEL_FRAME_FLY        equ #BCDD
KL_NEW_FAST_TICKER      equ #BCE0
KL_DEL_FAST_TICKER      equ #BCE6
KL_DISARM_EVENT         equ #BD0A

scr_reset               equ #BC0E
scr_set_border          equ #BC38
kl_rom_select           equ #B90f

; Telnet protocol
CMD         equ 255     ; IAC (Interpret As Command)

; Define RSX command table and data area
login
    ld bc, command_table
    ld hl, rsx_data_area
    call KL_LOG_EXT
    ret

command_table
    dw rsx_names
    jp term

rsx_names
    str 'TERM'       ; Terminal program
    db 0

rsx_data_area
    ds 4             ; 4 bytes for RSX workspace

    include "n4c-netinit-kv.s"
    include "main.s"
    include "ansiterm.s"
    include "screen.s"
    include "w5100.s"
    include "dns_simple.s"
    include "urlmenu_n4c.s"
    include "telnetfunc_n4c.s"
    include "negotiate.s"
    include "data.s"

SAVE 'N4CEWEN.BIN',#7000,$-#7000,AMSDOS
