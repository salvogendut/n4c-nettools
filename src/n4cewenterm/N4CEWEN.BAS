10 REM N4CWENTERM - Net4CPC Terminal
20 REM Network configuration is now in N4C.CFG
30 MODE 2
40 PRINT "Loading N4C-EWEN Terminal..."
50 PRINT
60 REM Load character set
70 MEMORY &6800-1
80 LOAD "charset.bin",&6800
90 REM Load terminal binary
100 LOAD "N4CEWEN.BIN",&7000
110 REM Install RSX
120 CALL &7000
130 REM Setup screen
140 MODE 2:BORDER 0:INK 0,0:INK 1,26
150 PRINT "Ewen-Term Communications program, v3.0 N4C installed."
160 PRINT
170 PRINT "Type |TERM to start terminal mode"
180 PRINT
190 REM Auto-start terminal (uncomment to enable)
200 REM |TERM
