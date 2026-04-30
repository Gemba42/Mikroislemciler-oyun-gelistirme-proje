; ============================================================
;  ASTEROID EVASION - Big Asteroid Update
;  For emu8086 / DOSBox (16-bit real mode, text mode 80x25)
; ============================================================
.MODEL SMALL
.STACK 200h

; ---- BIOS / DOS equates ----------------------------------------
VIDEO_INT    EQU 10h
DOS_INT      EQU 21h
BIOS_KBD     EQU 16h

; ---- Colour attributes -----------------------------------------
CLR_BG       EQU 01h   ; Dark blue
CLR_PLAYER   EQU 0Eh   ; Yellow
CLR_ASTEROID EQU 0Ch   ; Red
CLR_SHIELD   EQU 0Bh   ; Cyan
CLR_TEXT     EQU 0Fh   ; White
CLR_TITLE    EQU 1Fh   ; White on blue

; ---- Game constants --------------------------------------------
SCREEN_W     EQU 40
PLAY_TOP     EQU 2
PLAY_BOT     EQU 23
PLAY_LEFT    EQU 1
PLAY_RIGHT   EQU 38
MAX_SMALL    EQU 7
MAX_BIG      EQU 3
START_LIVES  EQU 1
MAX_LIVES    EQU 3
SHIELD_PROB  EQU 80
ROCK_PROB    EQU 8

; ---- Keyboard scan codes ---------------------------------------
KEY_LEFT     EQU 4Bh
KEY_RIGHT    EQU 4Dh
KEY_ESC      EQU 01h

; ============================================================
.DATA
player_x     DB  20
player_lives DB  START_LIVES
player_dead  DB  0
score_lo     DW  0
score_hi     DW  0

; ---- Small Asteroids (1 char: *) -------------------------------
s_col        DB  MAX_SMALL DUP(0)
s_row        DB  MAX_SMALL DUP(PLAY_TOP)
s_delay_max  DB  MAX_SMALL DUP(1)
s_delay_cur  DB  MAX_SMALL DUP(1)

; ---- Big Asteroids (2 chars: **) -------------------------------
b_col        DB  MAX_BIG DUP(0)
b_row        DB  MAX_BIG DUP(PLAY_TOP)
b_delay_max  DB  MAX_BIG DUP(1)
b_delay_cur  DB  MAX_BIG DUP(1)

shld_col     DB  0
shld_row     DB  0
shld_active  DB  0

rand_seed    DW  1234h

score_val    DW  0          ; Current score
score_tick   DB  0          ; Counter to slow down score gain
score_rate   EQU 10         ; Increase score every 10 game loops
score_buf    DB  '00000', '$'
  

msg_title    DB  ' ASTROID KACIS  [ESC] CIKIS ', '$'
msg_lives    DB  'CAN: $'
msg_score    DB  'SKOR: $'
msg_gameover DB  ' OYUN BITTI ! $'

; ============================================================
.CODE
START:
    MOV  AX, @DATA
    MOV  DS, AX
    MOV  AX, 0001h
    INT  VIDEO_INT
    MOV  AH, 01h
    MOV  CX, 2607h
    INT  VIDEO_INT
    XOR  AX, AX
    INT  1Ah
    MOV  [rand_seed], DX

    CALL ClearPlayfield
    CALL DrawHUD

GAME_LOOP:
    CALL DoDelay
    CALL IncScore
    CALL MoveAsteroids
    CALL SpawnAsteroid
    CALL HandleShield
    CALL CheckCollisions
    CALL ReadKey
    CALL DrawAll
    CALL DrawHUD
    CMP  BYTE PTR [player_dead], 1
    JNE  GAME_LOOP

GAME_OVER:
    MOV  DH, 12
    MOV  DL, 10
    MOV  BL, 0C0h
    LEA  SI, msg_gameover
    CALL PrintStr
    MOV  AH, 00h
    INT  BIOS_KBD
    MOV  AX, 4C00h
    INT  DOS_INT

; ============================================================
; PROCEDURES
; ============================================================

DoDelay PROC NEAR
    PUSH CX
    MOV DX, 2
DL_OUTER:
    MOV CX, 0FFFFh
DL_INNER:
    LOOP DL_INNER
    DEC DX
    JNZ  DL_OUTER
    POP CX
    RET
DoDelay ENDP

GetRand PROC NEAR
    PUSH DX
    MOV  AX, [rand_seed]
    MOV  DX, 8405h
    MUL  DX
    INC  AX
    MOV  [rand_seed], AX
    MOV  AL, AH
    XOR  AH, AH
    POP  DX
    RET
GetRand ENDP

MoveAsteroids PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    ; --- Move Small ---
    MOV SI, 0
MA_S_LOOP:
    CMP SI, MAX_SMALL
    JGE MA_B_START
    CMP BYTE PTR [s_col+SI], 0
    JE  MA_S_NEXT
    DEC BYTE PTR [s_delay_cur+SI]
    JNZ MA_S_NEXT
    MOV AL, [s_delay_max+SI]
    MOV [s_delay_cur+SI], AL
    MOV DL, [s_col+SI]
    MOV DH, [s_row+SI]
    CALL EraseAt
    INC BYTE PTR [s_row+SI]
    CMP BYTE PTR [s_row+SI], PLAY_BOT+1
    JL  MA_S_NEXT
    MOV BYTE PTR [s_col+SI], 0
MA_S_NEXT:
    INC SI
    JMP MA_S_LOOP

MA_B_START:
    ; --- Move Big ---
    MOV SI, 0
MA_B_LOOP:
    CMP SI, MAX_BIG
    JGE MA_DONE
    CMP BYTE PTR [b_col+SI], 0
    JE  MA_B_NEXT
    DEC BYTE PTR [b_delay_cur+SI]
    JNZ MA_B_NEXT
    MOV AL, [b_delay_max+SI]
    MOV [b_delay_cur+SI], AL
    MOV DL, [b_col+SI]
    MOV DH, [b_row+SI]
    CALL EraseAt
    INC DL
    CALL EraseAt
    INC BYTE PTR [b_row+SI]
    CMP BYTE PTR [b_row+SI], PLAY_BOT+1
    JL  MA_B_NEXT
    MOV BYTE PTR [b_col+SI], 0
MA_B_NEXT:
    INC SI
    JMP MA_B_LOOP

MA_DONE:
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
MoveAsteroids ENDP

SpawnAsteroid PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    CALL GetRand
    XOR AH, AH
    MOV BL, ROCK_PROB
    DIV BL
    CMP AH, 0
    JNE SA_EXIT

    CALL GetRand
    AND AL, 03h
    CMP AL, 0
    JE  TRY_BIG

TRY_SMALL:
    MOV SI, 0
SA_S_L:
    CMP SI, MAX_SMALL
    JGE SA_EXIT
    CMP BYTE PTR [s_col+SI], 0
    JE  SA_S_OK
    INC SI
    JMP SA_S_L

SA_S_OK:
    CALL GetRand
    XOR AH, AH
    MOV BL, 37
    DIV BL
    ADD AH, PLAY_LEFT
    MOV [s_col+SI], AH
    MOV BYTE PTR [s_row+SI], PLAY_TOP
    CALL GetSpeed
    MOV [s_delay_max+SI], AL
    MOV [s_delay_cur+SI], AL
    JMP SA_EXIT

TRY_BIG:
    MOV SI, 0
SA_B_L:
    CMP SI, MAX_BIG
    JGE TRY_SMALL
    CMP BYTE PTR [b_col+SI], 0
    JE  SA_B_OK
    INC SI
    JMP SA_B_L

SA_B_OK:
    CALL GetRand
    XOR AH, AH
    MOV BL, 36
    DIV BL
    ADD AH, PLAY_LEFT
    MOV [b_col+SI], AH
    MOV BYTE PTR [b_row+SI], PLAY_TOP
    CALL GetSpeed
    MOV [b_delay_max+SI], AL
    MOV [b_delay_cur+SI], AL

SA_EXIT:
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
SpawnAsteroid ENDP

GetSpeed PROC NEAR
    CALL GetRand
    XOR AH, AH
    MOV BL, 3
    DIV BL
    INC AH
    MOV AL, AH
    RET
GetSpeed ENDP

CheckCollisions PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV AL, [player_x]
    MOV BL, PLAY_BOT
    
    ; Small Collisions
    MOV SI, 0
CC_S:
    CMP SI, MAX_SMALL
    JGE CC_B
    CMP BYTE PTR [s_col+SI], 0
    JE  CC_S_N
    CMP [s_row+SI], BL
    JNE CC_S_N
    CMP [s_col+SI], AL
    JE  HIT_S
CC_S_N:
    INC SI
    JMP CC_S

HIT_S:
    MOV BYTE PTR [s_col+SI], 0
    DEC BYTE PTR [player_lives]
    JMP CC_CHECK_DEAD

CC_B:
    ; Big Collisions
    MOV SI, 0
CC_B_L:
    CMP SI, MAX_BIG
    JGE CC_SHLD
    CMP BYTE PTR [b_col+SI], 0
    JE  CC_B_N
    CMP [b_row+SI], BL
    JNE CC_B_N
    MOV CL, [b_col+SI]
    CMP AL, CL
    JE  HIT_B
    INC CL
    CMP AL, CL
    JE  HIT_B
CC_B_N:
    INC SI
    JMP CC_B_L

HIT_B:
    MOV BYTE PTR [b_col+SI], 0
    DEC BYTE PTR [player_lives]

CC_CHECK_DEAD:
    CMP BYTE PTR [player_lives], 0
    JG  CC_SHLD
    MOV BYTE PTR [player_dead], 1

CC_SHLD:
    CMP BYTE PTR [shld_active], 0
    JE  CC_DONE
    CMP [shld_row], BL
    JNE CC_DONE
    MOV CL, [shld_col]
    CMP AL, CL
    JNE CC_DONE
    MOV BYTE PTR [shld_active], 0
    CMP BYTE PTR [player_lives], MAX_LIVES
    JGE CC_DONE
    INC BYTE PTR [player_lives]

CC_DONE:
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
CheckCollisions ENDP

DrawAll PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    ; Player
    MOV DH, PLAY_BOT
    MOV DL, [player_x]
    MOV AL, '^'
    MOV BL, CLR_PLAYER
    CALL PrintChar
    
    ; Trail Cleanup
    MOV DL, [player_x]
    DEC DL
    CALL EraseAt
    MOV DL, [player_x]
    INC DL
    CALL EraseAt

    ; Small Rocks
    MOV SI, 0
D_S:
    CMP SI, MAX_SMALL
    JGE D_B
    CMP BYTE PTR [s_col+SI], 0
    JE  D_S_N
    MOV DL, [s_col+SI]
    MOV DH, [s_row+SI]
    MOV AL, '*'
    MOV BL, CLR_ASTEROID
    CALL PrintChar
D_S_N:
    INC SI
    JMP D_S

D_B:
    ; Big Rocks
    MOV SI, 0
D_B_L:
    CMP SI, MAX_BIG
    JGE D_SHLD
    CMP BYTE PTR [b_col+SI], 0
    JE  D_B_N
    MOV DL, [b_col+SI]
    MOV DH, [b_row+SI]
    MOV AL, '<'
    MOV BL, CLR_ASTEROID
    CALL PrintChar
    MOV AL, '>'
    INC DL
    CALL PrintChar
D_B_N:
    INC SI
    JMP D_B_L

D_SHLD:
    CMP BYTE PTR [shld_active], 0
    JE  D_DONE
    MOV DL, [shld_col]
    MOV DH, [shld_row]
    MOV AL, 'O'
    MOV BL, CLR_SHIELD
    CALL PrintChar

D_DONE:
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DrawAll ENDP

; --- Reused Utility Procedures ---
ClearPlayfield PROC NEAR
    MOV DH, PLAY_TOP
CP_R: MOV DL, 0
CP_C: CALL SetCursor
    MOV AH, 09h
    MOV AL, ' '
    MOV BL, CLR_BG
    MOV CX, 1
    INT VIDEO_INT
    INC DL
    CMP DL, SCREEN_W
    JL CP_C
    INC DH
    CMP DH, PLAY_BOT+1
    JL CP_R
    RET
ClearPlayfield ENDP

SetCursor PROC NEAR
    MOV AH, 02h
    MOV BH, 0
    INT VIDEO_INT
    RET
SetCursor ENDP

PrintChar PROC NEAR
    CALL SetCursor
    MOV AH, 09h
    MOV BH, 0
    MOV CX, 1
    INT VIDEO_INT
    RET
PrintChar ENDP

PrintStr PROC NEAR
PS_L: MOV AL, [SI]
    CMP AL, '$'
    JE  PS_D
    CALL PrintChar
    INC SI
    INC DL
    JMP PS_L
PS_D: RET
PrintStr ENDP

DrawHUD PROC NEAR
    ; 1) DO THE MATH FIRST
    ; This fills the buffer. We do this first so the 'DX' register 
    ; used in math doesn't mess up our coordinates later.
    CALL ScoreToStr     

    ; 2) DRAW TITLE
    MOV DH, 0
    MOV DL, 0
    MOV BL, CLR_TITLE
    LEA SI, msg_title
    CALL PrintStr

    ; 3) DRAW LIVES
    MOV DH, 1
    MOV DL, 1
    MOV BL, CLR_TEXT
    LEA SI, msg_lives
    CALL PrintStr
    MOV AL, [player_lives]
    ADD AL, '0'
    MOV BL, 0Ah 
    CALL PrintChar

    ; 4) DRAW SCORE LABEL
    MOV DH, 1
    MOV DL, 10
    MOV BL, CLR_TEXT
    LEA SI, msg_score
    CALL PrintStr       

    ; 5) DRAW SCORE NUMBERS
    ; Since PrintStr for "SKOR: " moves DL forward, 
    ; we just need to ensure we are at the right spot.
    MOV DH, 1
    MOV DL, 16
    CALL SetCursor      ; Force cursor to column 16
    LEA SI, score_buf
    MOV BL, 0Eh         ; Yellow score
    CALL PrintStr
    RET
DrawHUD ENDP

ScoreToStr PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX   ; <--- SAVE COORDINATES
    PUSH DI
    
    ; Clear buffer
    LEA DI, score_buf
    MOV CX, 5
    MOV AL, '0'
    REP STOSB
    
    ; Convert score_val (or score_lo)
    MOV AX, [score_val] ; Use whichever variable name you have
    LEA DI, score_buf+4 
    MOV BX, 10
    
S_CONV:
    XOR DX, DX          ; Preparing DX for division
    DIV BX              ; AX / 10, Remainder in DX
    ADD DL, '0'
    MOV [DI], DL
    DEC DI
    CMP AX, 0
    JZ  S_DONE
    CMP DI, OFFSET score_buf - 1
    JNE S_CONV

S_DONE:
    POP DI
    POP DX    ; <--- RESTORE COORDINATES
    POP CX
    POP BX
    POP AX
    RET
ScoreToStr ENDP

IncScore PROC NEAR
    INC BYTE PTR [score_tick]
    MOV AL, [score_tick]
    CMP AL, score_rate
    JL  IS_D                ; Only increment score if tick reaches rate
    
    MOV BYTE PTR [score_tick], 0
    INC WORD PTR [score_val]
    
    ; Optional: Cap score at 99999 for the buffer
    CMP WORD PTR [score_val], 9999
    JBE IS_D
    MOV WORD PTR [score_val], 9999
IS_D: 
    RET
IncScore ENDP

EraseAt PROC NEAR
    MOV AL, ' '
    MOV BL, CLR_BG
    CALL PrintChar
    RET
EraseAt ENDP

HandleShield PROC NEAR
    CMP BYTE PTR [shld_active], 0
    JNE HS_M
    CALL GetRand
    XOR AH, AH
    MOV BL, SHIELD_PROB
    DIV BL
    CMP AH, 0
    JNE HS_X
    CALL GetRand
    XOR AH, AH
    MOV BL, 37
    DIV BL
    ADD AH, PLAY_LEFT
    MOV [shld_col], AH
    MOV BYTE PTR [shld_row], PLAY_TOP
    MOV BYTE PTR [shld_active], 1
    RET
HS_M:
    MOV DL, [shld_col]
    MOV DH, [shld_row]
    CALL EraseAt
    INC BYTE PTR [shld_row]
    CMP BYTE PTR [shld_row], PLAY_BOT+1
    JL HS_X
    MOV BYTE PTR [shld_active], 0
HS_X: RET
HandleShield ENDP

ReadKey PROC NEAR
    MOV AH, 01h
    INT 16h
    JZ RK_X
    MOV AH, 00h
    INT 16h
    CMP AH, KEY_ESC
    JNE RK_L
    MOV BYTE PTR [player_dead], 1
RK_L: CMP AH, KEY_LEFT
    JNE RK_R
    CMP BYTE PTR [player_x], PLAY_LEFT+1
    JLE RK_X
    DEC BYTE PTR [player_x]
RK_R: CMP AH, KEY_RIGHT
    JNE RK_X
    CMP BYTE PTR [player_x], PLAY_RIGHT-1
    JGE RK_X
    INC BYTE PTR [player_x]
RK_X: RET
ReadKey ENDP

END START