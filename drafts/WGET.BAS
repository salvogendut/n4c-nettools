10 REM WGET - HTTP File Downloader for Net4CPC
20 REM Memory layout:
30 REM   &3E00: Hostname (null-terminated)
40 REM   &3E80: Path (null-terminated)
50 REM   &3F00: AMSDOS filename (11 bytes)
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
250 REM
260 REM Extract filename from path (last component after /)
270 REM
280 fname$=""
290 FOR i=LEN(path$) TO 1 STEP -1
300   IF MID$(path$,i,1)="/" THEN GOTO 330
310   fname$=MID$(path$,i,1)+fname$
320 NEXT i
330 REM
340 REM If no filename found, use default
350 REM
360 IF fname$="" THEN fname$="INDEX.HTM"
370 REM
380 REM Convert filename to AMSDOS format (8.3)
390 REM
400 dot=INSTR(fname$,".")
410 IF dot=0 THEN name$=fname$:ext$=""
420 IF dot>0 THEN name$=LEFT$(fname$,dot-1):ext$=MID$(fname$,dot+1)
430 REM Truncate and uppercase
440 name$=LEFT$(name$,8)
450 ext$=LEFT$(ext$,3)
460 name$=UPPER$(name$)
470 ext$=UPPER$(ext$)
480 REM Pad with spaces
490 WHILE LEN(name$)<8:name$=name$+" ":WEND
500 WHILE LEN(ext$)<3:ext$=ext$+" ":WEND
510 amsfname$=name$+ext$
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
800 REM Write AMSDOS filename to &3F00
810 addr=&3F00
820 FOR i=1 TO 11
830   POKE addr,ASC(MID$(amsfname$,i,1))
840   addr=addr+1
850 NEXT i
860 POKE &3F0B,11:REM filename length
870 REM
880 REM Load and run binary
890 REM
900 LOAD"WGET.BIN",&4000
910 CALL &4000
920 END
