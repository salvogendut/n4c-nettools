10 REM WGET - HTTP File Downloader for Net4CPC
20 REM Memory layout:
30 REM   &3E00: Hostname (null-terminated)
40 REM   &3E80: Path (null-terminated)
50 REM   &3F00: Filename for CAS_OUT_OPEN
60 REM   &3F0B: Filename length (1 byte)
70 MODE 2:MEMORY &3DFF
80 PRINT "WGET for Net4CPC"
90 PRINT "================"
100 PRINT
110 INPUT "Enter URL: ";url$
120 IF url$="" THEN PRINT "Error: Empty URL":END
130 REM
140 REM Parse URL - strip http:// if present
150 REM
160 IF LEFT$(url$,7)="http://" THEN url$=MID$(url$,8)
170 IF LEFT$(url$,8)="https://" THEN PRINT "Error: HTTPS not supported":END
180 REM
190 REM Find first / to split host from path
200 REM
210 slash=INSTR(url$,"/")
220 IF slash=0 THEN host$=url$:path$="/":GOTO 260
230 host$=LEFT$(url$,slash-1)
240 path$=MID$(url$,slash)
245 temp$="":FOR i=1 TO LEN(path$):c=ASC(MID$(path$,i,1)):IF c>=97 AND c<=122 THEN c=c-32:temp$=temp$+CHR$(c):NEXT i:path$=temp$
250 REM
260 REM Extract port from host (e.g. "host:8080") and filename from path
261 prt=80
262 colon=INSTR(host$,":")
263 IF colon>0 THEN prt=VAL(MID$(host$,colon+1)):host$=LEFT$(host$,colon-1)
270 REM
280 dfn$=""
290 FOR i=LEN(path$) TO 1 STEP -1
300   IF MID$(path$,i,1)="/" THEN GOTO 330
310   dfn$=MID$(path$,i,1)+dfn$
320 NEXT i
330 REM
340 REM If no filename found, use default
350 REM
360 IF dfn$="" THEN dfn$="INDEX.HTM"
370 REM
380 REM Convert filename to AMSDOS format (8.3)
390 REM
400 dot=INSTR(dfn$,".")
410 IF dot=0 THEN name$=dfn$:ext$=""
420 IF dot>0 THEN name$=LEFT$(dfn$,dot-1):ext$=MID$(dfn$,dot+1)
430 REM Truncate and uppercase
440 name$=LEFT$(name$,8)
450 ext$=LEFT$(ext$,3)
460 temp$="":FOR i=1 TO LEN(name$):c=ASC(MID$(name$,i,1)):IF c>=97 AND c<=122 THEN c=c-32
465 temp$=temp$+CHR$(c):NEXT i:name$=temp$
470 temp$="":FOR i=1 TO LEN(ext$):c=ASC(MID$(ext$,i,1)):IF c>=97 AND c<=122 THEN c=c-32
475 temp$=temp$+CHR$(c):NEXT i:ext$=temp$
480 REM Pad with spaces
490 WHILE LEN(name$)<8:name$=name$+" ":WEND
500 WHILE LEN(ext$)<3:ext$=ext$+" ":WEND
510 amsdfn$=name$+ext$
520 REM
530 REM Display parsed components
540 REM
550 PRINT
560 PRINT "Host: ";host$
570 PRINT "Path: ";path$
580 PRINT "Save as: ";LEFT$(name$,8);".";LEFT$(ext$,3)
590 PRINT
600 INPUT "Continue? (Y/N) ";yn$
610 IF yn$<>"Y" AND yn$<>"y" THEN PRINT "Cancelled.":END
620 REM
630 REM Write to memory
640 REM
650 PRINT "Preparing download..."
660 REM Write hostname to &3E00
670 addr=&3E00
680 FOR i=1 TO LEN(host$)
690   POKE addr,ASC(MID$(host$,i,1))
700   addr=addr+1
710 NEXT i
720 POKE addr,0:REM null terminator
730 REM Write path to &3E80
740 addr=&3E80
750 FOR i=1 TO LEN(path$)
760   POKE addr,ASC(MID$(path$,i,1))
770   addr=addr+1
780 NEXT i
790 POKE addr,0:REM null terminator
800 REM Build dotted filename for CAS (e.g. HELLO.TXT)
805 nm$=name$
806 WHILE LEN(nm$)>0 AND RIGHT$(nm$,1)=" ":nm$=LEFT$(nm$,LEN(nm$)-1):WEND
807 ex$=ext$
808 WHILE LEN(ex$)>0 AND RIGHT$(ex$,1)=" ":ex$=LEFT$(ex$,LEN(ex$)-1):WEND
809 IF LEN(ex$)>0 THEN cf$=nm$+"."+ex$ ELSE cf$=nm$
810 addr=&3F00
815 FOR i=1 TO LEN(cf$)
820   POKE addr,ASC(MID$(cf$,i,1))
825   addr=addr+1
830 NEXT i
840 POKE &3F0B,LEN(cf$):REM filename length for CAS_OUT_OPEN B register
861 POKE &3F0C,prt MOD 256:REM port low byte
862 POKE &3F0D,INT(prt/256):REM port high byte
870 REM
880 REM Load and run binary
890 REM
900 LOAD"WGET.BIN",&4000
910 CALL &4000
920 END
