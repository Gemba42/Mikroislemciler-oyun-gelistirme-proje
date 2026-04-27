; ============================================================
;  ASTEROID EVASION - x86 Assembly Game
;  For emu8086 / DOSBox (16-bit real mode, text mode 80x25)
;
;  Controls : LEFT ARROW / RIGHT ARROW to move
;  Objective: Dodge falling asteroids (*), pick up shields (O)
;  Score    : Increases every game tick you survive
;  Lives    : Start with 3; shields (O) add +1 (max 5)
;  Game ends: 0 lives remaining
; ============================================================

.MODEL SMALL
.STACK 200h

; ---- BIOS / DOS equates ----------------------------------------
VIDEO_INT    EQU 10h
DOS_INT      EQU 21h
BIOS_KBD     EQU 16h

; ---- Colour attributes -----------------------------------------
CLR_BG       EQU 01h   ; Dark blue background, blue text (space)
CLR_PLAYER   EQU 0Eh   ; Yellow  - player ship
CLR_ASTEROID EQU 0Ch   ; Red     - asteroid
CLR_SHIELD   EQU 0Bh   ; Cyan    - shield pickup
CLR_TEXT     EQU 0Fh   ; White   - HUD text
CLR_SHLD_ON  EQU 0Ah   ; Green   - lives digit when shielded
CLR_TITLE    EQU 1Fh   ; White on blue - title bar

; ---- Game constants --------------------------------------------
SCREEN_W     EQU 40
SCREEN_H     EQU 25
PLAY_TOP     EQU 2     ; first playfield row (rows 0-1 = HUD)
PLAY_BOT     EQU 23    ; last playfield row  (row 24 = status)
PLAY_LEFT    EQU 1
PLAY_RIGHT   EQU 38

MAX_ROCKS    EQU 10     ; max simultaneous asteroids
MAX_LIVES    EQU 3
START_LIVES  EQU 1

SHIELD_PROB  EQU 50    ; 1-in-N chance a shield spawns each tick
ROCK_PROB    EQU 8    ; 1-in-N chance each rock-slot spawns each tick

TICK_DELAY   EQU 4000h ; inner loop count for ~speed delay

; ---- Keyboard scan codes (extended) ----------------------------
KEY_LEFT     EQU 4Bh
KEY_RIGHT    EQU 4Dh
KEY_ESC      EQU 01h

; ============================================================
.DATA

; ---- Player state ----------------------------------------------
player_x     DB  20          ; current column (1-78)
player_lives DB  START_LIVES
player_dead  DB  0           ; 1 = game over
score_lo     DW  0           ; 32-bit score
score_hi     DW  0

; ---- Asteroid table  (col, row) each  -------------------------
; col=0 means slot is inactive
rock_col     DB  MAX_ROCKS DUP(0)
rock_row     DB  MAX_ROCKS DUP(PLAY_TOP)

; ---- Shield pickup  (col, row, active) -------------------------
shld_col     DB  0
shld_row     DB  0
shld_active  DB  0

; ---- Pseudo-random seed ----------------------------------------
rand_seed    DW  1234h

; ---- Score display buffer  (8 decimal digits) ------------------
score_buf    DB  8 DUP('0'), '$'

; ---- String messages -------------------------------------------
msg_title    DB  ' ASTROID KACIS  [ESC] CIKIS ', '$'
msg_lives    DB  'CAN: $'
msg_score    DB  'SKOR: $'
msg_gameover DB  ' OYUN BITTI ! $'
msg_shielded DB  '*SHIELD*$'

; ============================================================
.CODE
START:
    ; --- init DS ------------------------------------------------
    MOV  AX, @DATA
    MOV  DS, AX

    ; --- set text mode 80x25 (INT 10h, AH=0, AL=3) -------------
    MOV  AX, 0001h
    INT  VIDEO_INT

    ; --- hide cursor --------------------------------------------
    MOV  AH, 01h
    MOV  CX, 2607h      ; start=26 end=7 -> invisible
    INT  VIDEO_INT

    ; --- seed RNG from BIOS timer (INT 1Ah) ---------------------
    XOR  AX, AX
    INT  1Ah            ; CX:DX = tick count
    MOV  [rand_seed], DX

    ; --- draw initial HUD & background --------------------------
    CALL ClearPlayfield
    CALL DrawHUD

; ============================================================
GAME_LOOP:
    ; 1) Delay (simple busy wait)
    CALL DoDelay

    ; 2) Increase score
    CALL IncScore

    ; 3) Move asteroids down
    CALL MoveAsteroids

    ; 4) Maybe spawn new asteroid
    CALL SpawnAsteroid

    ; 5) Handle shield pickup
    CALL HandleShield

    ; 6) Check collisions
    CALL CheckCollisions

    ; 7) Read keyboard
    CALL ReadKey

    ; 8) Draw everything
    CALL DrawAll

    ; 9) Update HUD
    CALL DrawHUD

    ; 10) Check game-over flag
    CMP  BYTE PTR [player_dead], 1
    JE   GAME_OVER

    ; 11) Check ESC
    JMP  GAME_LOOP

; ============================================================
GAME_OVER:
    ; Flash "GAME OVER" at centre
    MOV  DH, 12         ; row
    MOV  DL, 5         ; col
    MOV  BL, 0C0h       ; red on black blinking
    LEA  SI, msg_gameover
    CALL PrintStr

    ; Wait for any key
    MOV  AH, 00h
    INT  BIOS_KBD

    ; Restore cursor & return to DOS
    MOV  AH, 01h
    MOV  CX, 0607h
    INT  VIDEO_INT
    MOV  AX, 4C00h
    INT  DOS_INT

; ============================================================
; DoDelay - busy wait for game speed
; ============================================================
DoDelay PROC NEAR
    PUSH CX
    MOV DX, 2      ; Outer loop (Adjust this for speed)
DL_OUTER:
    MOV CX, 0FFFFh  ; Inner loop (65535)
DL_INNER:
    LOOP DL_INNER
    DEC DX
    JNZ DL_OUTER
    POP CX
    RET
DoDelay ENDP
; ============================================================
; GetRand  -> AX = pseudo-random 0..255
; Uses a 16-bit LCG with proper constants. Returns high byte.
; ============================================================
GetRand PROC NEAR
    MOV  AX, [rand_seed]
    MOV  DX, 6255h          ; Proper LCG multiplier (25173)
    MUL  DX                 ; DX:AX = seed * 6255h
    ADD  AX, 3619h          ; Proper odd increment (13849)
    MOV  [rand_seed], AX    ; Save the full 16-bit state
    
    ; The most random bits of an LCG are the highest bits.
    ; We return the HIGH byte in AL, instead of the low byte.
    MOV  AL, AH             
    XOR  AH, AH             ; Zero out AH
    RET
GetRand ENDP

; ============================================================
; ClearPlayfield - fill rows 2-23 with spaces, dark blue attr
; ============================================================
ClearPlayfield PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    MOV  DH, PLAY_TOP
CF_ROW:
    MOV  DL, 0
CF_COL:
    CALL SetCursor
    MOV  AH, 09h        ; write char+attr
    MOV  AL, ' '
    MOV  BH, 0
    MOV  BL, CLR_BG
    MOV  CX, 1
    INT  VIDEO_INT
    INC  DL
    CMP  DL, SCREEN_W
    JL   CF_COL
    INC  DH
    CMP  DH, PLAY_BOT+1
    JL   CF_ROW
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
ClearPlayfield ENDP

; ============================================================
; SetCursor  DH=row DL=col
; ============================================================
SetCursor PROC NEAR
    PUSH AX
    PUSH BX
    MOV  AH, 02h
    MOV  BH, 0
    INT  VIDEO_INT
    POP  BX
    POP  AX
    RET
SetCursor ENDP

; ============================================================
; PrintChar  AL=char BL=attr DH=row DL=col
; ============================================================
PrintChar PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    CALL SetCursor
    MOV  AH, 09h
    MOV  BH, 0
    MOV  CX, 1
    INT  VIDEO_INT
    POP  CX
    POP  BX
    POP  AX
    RET
PrintChar ENDP

; ============================================================
; PrintStr  SI->string$ BL=attr DH=row DL=col
; ============================================================
PrintStr PROC NEAR
    PUSH AX
    PUSH CX
    PUSH SI
PS_LOOP:
    MOV  AL, [SI]
    CMP  AL, '$'
    JE   PS_DONE
    CALL PrintChar
    INC  SI
    INC  DL
    JMP  PS_LOOP
PS_DONE:
    POP  SI
    POP  CX
    POP  AX
    RET
PrintStr ENDP

; ============================================================
; DrawHUD - top bar row 0 and row 1 separator
; ============================================================
DrawHUD PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    ; --- Title bar (row 0) -------------------------------------
    MOV  DH, 0
    MOV  DL, 0
    MOV  BL, CLR_TITLE
    LEA  SI, msg_title
    CALL PrintStr

    ; --- Row 1: LIVES label ------------------------------------
    MOV  DH, 1
    MOV  DL, 1
    MOV  BL, CLR_TEXT
    LEA  SI, msg_lives
    CALL PrintStr

    ; lives value (DL now at position after label "LIVES: ")
    MOV  AL, [player_lives]
    ADD  AL, '0'
    MOV  BL, CLR_SHLD_ON
    CALL PrintChar
    INC  DL

    ; --- SCORE label -------------------------------------------
    MOV  DL, 10
    MOV  BL, CLR_TEXT
    LEA  SI, msg_score
    CALL PrintStr

    ; convert score to decimal string
    CALL ScoreToStr

    ; print score_buf
    LEA  SI, score_buf
    MOV  BL, 0Eh        ; yellow
    CALL PrintStr

    POP  SI
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
DrawHUD ENDP

; ============================================================
; ScoreToStr - converts score_hi:score_lo to score_buf decimal
; Simple: only handles 16-bit score_lo (max 65535) for clarity
; For a real game use full 32-bit; here we keep it simple.
; ============================================================
ScoreToStr PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH DI

    ; Fill buf with '0' first
    LEA  DI, score_buf
    MOV  CX, 8
    MOV  AL, '0'
FILL_ZEROS:
    MOV  [DI], AL
    INC  DI
    LOOP FILL_ZEROS

    ; Convert score_lo to decimal into buf[7..0]
    MOV  AX, [score_lo]
    LEA  DI, score_buf+7  ; start from rightmost digit
    MOV  BX, 10
STS_LOOP:
    XOR  DX, DX
    DIV  BX               ; AX=quotient DX=remainder
    ADD  DL, '0'
    MOV  [DI], DL
    DEC  DI
    CMP  AX, 0
    JNE  STS_LOOP

    POP  DI
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
ScoreToStr ENDP

; ============================================================
; IncScore - increment 32-bit score
; ============================================================
IncScore PROC NEAR
    INC  WORD PTR [score_lo]
    JNZ  IS_DONE
    INC  WORD PTR [score_hi]
IS_DONE:
    RET
IncScore ENDP

; ============================================================
; EraseAt  DH=row DL=col  - erase one character (space)
; ============================================================
EraseAt PROC NEAR
    PUSH AX
    PUSH BX
    MOV  AL, ' '
    MOV  BL, CLR_BG
    CALL PrintChar
    POP  BX
    POP  AX
    RET
EraseAt ENDP

; ============================================================
; MoveAsteroids - move each active asteroid down by 1
; ============================================================
MoveAsteroids PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV  SI, 0
MA_LOOP:
    CMP  SI, MAX_ROCKS
    JGE  MA_DONE

    MOV  AL, [rock_col+SI]
    CMP  AL, 0
    JE   MA_NEXT         ; inactive

    ; erase old position
    MOV  DL, [rock_col+SI]
    MOV  DH, [rock_row+SI]
    CALL EraseAt

    ; move down
    INC  BYTE PTR [rock_row+SI]

    ; if off screen, deactivate
    MOV  AL, [rock_row+SI]
    CMP  AL, PLAY_BOT+1
    JL   MA_NEXT
    MOV  BYTE PTR [rock_col+SI], 0   ; deactivate
    MOV  BYTE PTR [rock_row+SI], PLAY_TOP

MA_NEXT:
    INC  SI
    JMP  MA_LOOP
MA_DONE:
    POP  SI
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
MoveAsteroids ENDP

; ============================================================
; SpawnAsteroid - maybe spawn in a free slot
; ============================================================
SpawnAsteroid PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    ; Roll dice: prob 1/ROCK_PROB
    CALL GetRand
    XOR  AH,AH
    MOV  BL, ROCK_PROB
    DIV  BL             ; AH = remainder
    CMP  AH, 0
    JNE  SA_DONE        ; not lucky this tick

    ; Find free slot
    MOV  SI, 0
SA_FIND:
    CMP  SI, MAX_ROCKS
    JGE  SA_DONE
    CMP  BYTE PTR [rock_col+SI], 0
    JE   SA_GOT
    INC  SI
    JMP  SA_FIND
SA_GOT:
    ; random column PLAY_LEFT..PLAY_RIGHT
    CALL GetRand    
    XOR  AH,AH
    MOV  BL, (PLAY_RIGHT - PLAY_LEFT + 1)
    DIV  BL
    ADD  AH, PLAY_LEFT
    MOV  [rock_col+SI], AH
    MOV  BYTE PTR [rock_row+SI], PLAY_TOP
SA_DONE:
    POP  SI
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
SpawnAsteroid ENDP

; ============================================================
; HandleShield - spawn / move shield pickup
; ============================================================
HandleShield PROC NEAR
    PUSH AX
    PUSH BX
    PUSH DX

    CMP  BYTE PTR [shld_active], 0
    JNE  HS_MOVE

    ; Try to spawn
    CALL GetRand
    XOR  AH,AH
    MOV  BL, SHIELD_PROB
    DIV  BL
    CMP  AH, 0
    JNE  HS_DONE

    ; spawn at random col, top row
    CALL GetRand
    XOR  AH,AH
    MOV  BL, (PLAY_RIGHT - PLAY_LEFT + 1)
    DIV  BL
    ADD  AH, PLAY_LEFT
    MOV  [shld_col], AH
    MOV  BYTE PTR [shld_row], PLAY_TOP
    MOV  BYTE PTR [shld_active], 1
    JMP  HS_DONE

HS_MOVE:
    ; erase old
    MOV  DL, [shld_col]
    MOV  DH, [shld_row]
    CALL EraseAt
    ; move down
    INC  BYTE PTR [shld_row]
    MOV  AL, [shld_row]
    CMP  AL, PLAY_BOT+1
    JL   HS_DONE
    MOV  BYTE PTR [shld_active], 0   ; fell off

HS_DONE:
    POP  DX
    POP  BX
    POP  AX
    RET
HandleShield ENDP

; ============================================================
; CheckCollisions - player vs asteroids and shield
; ============================================================
CheckCollisions PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV  AL, [player_x]
    MOV  BL, PLAY_BOT       ; player is always on bottom row

    ; --- Check each asteroid ------------------------------------
    MOV  SI, 0
CC_LOOP:
    CMP  SI, MAX_ROCKS
    JGE  CC_SHIELD

    CMP  BYTE PTR [rock_col+SI], 0
    JE   CC_NEXT

    MOV  CL, [rock_col+SI]
    MOV  DH, [rock_row+SI]
    CMP  CL, AL             ; same col as player?
    JNE  CC_NEXT
    CMP  DH, BL             ; same row as player?
    JNE  CC_NEXT

    ; HIT!
    MOV  BYTE PTR [rock_col+SI], 0  ; remove asteroid
    DEC  BYTE PTR [player_lives]
    CMP  BYTE PTR [player_lives], 0
    JG   CC_NEXT            ; still alive
    MOV  BYTE PTR [player_dead], 1
    JMP  CC_DONE

CC_NEXT:
    INC  SI
    JMP  CC_LOOP

CC_SHIELD:
    ; --- Check shield pickup -----------------------------------
    CMP  BYTE PTR [shld_active], 0
    JE   CC_DONE
    MOV  CL, [shld_col]
    MOV  DH, [shld_row]
    CMP  CL, AL
    JNE  CC_DONE
    CMP  DH, BL
    JNE  CC_DONE

    ; Picked up shield!
    MOV  BYTE PTR [shld_active], 0
    MOV  AL, [player_lives]
    CMP  AL, MAX_LIVES
    JGE  CC_DONE
    INC  BYTE PTR [player_lives]

CC_DONE:
    POP  SI
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
CheckCollisions ENDP

; ============================================================
; ReadKey - non-blocking keyboard check
; ============================================================
ReadKey PROC NEAR
    PUSH AX
    PUSH BX

    ; check if key available (AH=01h, ZF=1 means no key)
    MOV  AH, 01h
    INT  BIOS_KBD
    JZ   RK_DONE        ; no key pressed

    ; consume the key (AH=00h)
    MOV  AH, 00h
    INT  BIOS_KBD       ; AL=ASCII, AH=scan code

    CMP  AL, 0          ; extended key?
    JNE  RK_CHECK_ESC
    ; extended - check AH
    CMP  AH, KEY_LEFT
    JE   RK_LEFT
    CMP  AH, KEY_RIGHT
    JE   RK_RIGHT
    JMP  RK_DONE

RK_CHECK_ESC:
    CMP  AH, KEY_ESC
    JNE  RK_DONE
    MOV  BYTE PTR [player_dead], 1
    JMP  RK_DONE

RK_LEFT:
    CMP  BYTE PTR [player_x], PLAY_LEFT+1
    JLE  RK_DONE
    DEC  BYTE PTR [player_x]
    JMP  RK_DONE

RK_RIGHT:
    CMP  BYTE PTR [player_x], PLAY_RIGHT-1
    JGE  RK_DONE
    INC  BYTE PTR [player_x]

RK_DONE:
    POP  BX
    POP  AX
    RET
ReadKey ENDP

; ============================================================
; DrawAll - draw player, asteroids, shield
; ============================================================
DrawAll PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    ; --- Draw player ship  ('^' character) ----------------------
    MOV  DH, PLAY_BOT
    MOV  DL, [player_x]
    MOV  AL, '^'
    MOV  BL, CLR_PLAYER
    CALL PrintChar

    ; erase one column left of player (trail cleanup)
    MOV  DL, [player_x]
    CMP  DL, PLAY_LEFT+1
    JLE  DA_SKIP_LEFT
    DEC  DL
    ; only erase if it's not an asteroid there
    CALL EraseAt
DA_SKIP_LEFT:
    MOV  DL, [player_x]
    CMP  DL, PLAY_RIGHT-1
    JGE  DA_SKIP_RIGHT
    INC  DL
    CALL EraseAt
DA_SKIP_RIGHT:

    ; --- Draw asteroids -----------------------------------------
    MOV  SI, 0
DA_ROCKS:
    CMP  SI, MAX_ROCKS
    JGE  DA_SHIELD

    MOV  AL, [rock_col+SI]
    CMP  AL, 0
    JE   DA_NEXT_ROCK

    MOV  DL, [rock_col+SI]
    MOV  DH, [rock_row+SI]
    MOV  AL, '*'
    MOV  BL, CLR_ASTEROID
    CALL PrintChar

DA_NEXT_ROCK:
    INC  SI
    JMP  DA_ROCKS

DA_SHIELD:
    ; --- Draw shield pickup -------------------------------------
    CMP  BYTE PTR [shld_active], 0
    JE   DA_DONE

    MOV  DL, [shld_col]
    MOV  DH, [shld_row]
    MOV  AL, 'O'
    MOV  BL, CLR_SHIELD
    CALL PrintChar

DA_DONE:
    POP  SI
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
DrawAll ENDP

END START    

