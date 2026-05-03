
.MODEL SMALL
.STACK 200h

; interruptlar
VIDEO_INT    EQU 10h
DOS_INT      EQU 21h
KBD_INT      EQU 16h
CLK_INT      EQU 1Ah

; renkler
CLR_PLAYER   EQU 0Eh   ; sari
CLR_ASTEROID EQU 0Ch   ; kirmizi
CLR_SHIELD   EQU 0Ah   ; yesil
CLR_TEXT     EQU 0Fh   ; beyaz

; oyun degerleri
SCREEN_W     EQU 40
PLAY_TOP     EQU 2
PLAY_BOT     EQU 23
PLAY_LEFT    EQU 1
PLAY_RIGHT   EQU 38
MAX_SMALL    EQU 7
MAX_BIG      EQU 3
MAX_LIVES    EQU 3
SHIELD_PROB  EQU 80
ROCK_PROB    EQU 8
BIG_PROB     EQU 4

; tus kodlari
KEY_LEFT     EQU 4Bh
KEY_RIGHT    EQU 4Dh
KEY_ESC      EQU 01h



.DATA  

; oyuncu
player_x     DB  20
player_lives DB  MAX_LIVES
player_dead  DB  0

; kucuk astroidler
s_col         DB  MAX_SMALL DUP(0)
s_row         DB  MAX_SMALL DUP(PLAY_TOP)
s_delay_max   DB  MAX_SMALL DUP(1)
s_delay_cur   DB  MAX_SMALL DUP(1)

; buyuk astroidler
b_col         DB  MAX_BIG DUP(0)
b_row         DB  MAX_BIG DUP(PLAY_TOP)
b_delay_max   DB  MAX_BIG DUP(1)
b_delay_cur   DB  MAX_BIG DUP(1)

; kalkan
shld_col      DB  0
shld_row      DB  0
shld_spawned  DB  0

; skor
score_val     DW  0          
score_tick    DB  0          
score_rate    EQU 10         
score_buf     DB  '0000', '$'
              
; random              
rand_seed     DW  1234h

; mesajlar
msg_title     DB  ' ASTROID KACIS  [ESC] CIKIS ', '$'
msg_lives     DB  'CAN: $'
msg_score     DB  'SKOR: $'
msg_gameover DB  ' OYUN BITTI ! $'





.CODE
START:

    ;ekrani ayarla,imleci gorunmez yap,seede baslangic deger ver.
    MOV  AX, @DATA
    MOV  DS, AX
    MOV  AX, 0001h
    INT  VIDEO_INT
    MOV  AH, 01h
    MOV  CX, 2607h
    INT  VIDEO_INT
    XOR  AX, AX
    INT  CLK_INT
    MOV  [rand_seed], DX

    CALL ClearPlayfield
    CALL DrawHUD
    CALL SpawnPlayer

GAME_LOOP:

    CALL Delay
    
    CALL MovePlayer
    
    CALL SpawnAstroid
    
    CALL MoveAsteroids
    
    CALL SpawnShield
    
    CALL MoveShield
    
    CALL CheckCollisions
    
    CALL UpdateScore
    
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
    INT  KBD_INT
    MOV  AX, 4C00h
    INT  DOS_INT


  
Delay PROC NEAR
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
Delay ENDP


;LCG kullanarak pseudo random sayi uret ve seedi degistir
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



ClearPlayfield PROC NEAR
    MOV AH, 06h          
    MOV AL, 0                 
    
    INT VIDEO_INT        
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
              
              
EraseAt PROC NEAR
    MOV AL, ' '
    CALL PrintChar
    RET
EraseAt ENDP


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


UpdateScore PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH DI

    ;skor degerini stringe cevir
    MOV AX, [score_val]
    LEA DI, score_buf + 3  
    MOV BX, 10
    MOV CX, 4              
    
CONV_LOOP:
    XOR DX, DX
    DIV BX                 
    ADD DL, '0'            
    MOV [DI], DL           
    DEC DI
    LOOP CONV_LOOP

    ;skor stringini yazdir
    MOV DH, 1              
    MOV DL, 16             
    MOV BL, CLR_PLAYER     
    LEA SI, score_buf
    CALL PrintStr

    POP DI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
UpdateScore ENDP

SpawnPlayer PROC NEAR
    MOV BYTE PTR [player_x], 20      
    MOV BYTE PTR [player_lives], MAX_LIVES   
    MOV BYTE PTR [player_dead], 0    
    RET
SpawnPlayer ENDP



MovePlayer PROC NEAR
    MOV AH, 01h             
    INT KBD_INT
    JZ  MP_DONE              

    MOV AH, 00h              
    INT KBD_INT

    ;tus escape ise oyunu bitir
    CMP AH, KEY_ESC
    JNE MP_LEFT
    MOV BYTE PTR [player_dead], 1
    RET                      


MP_LEFT:
    ;ekran sonuysa sola ilerletme
    CMP AH, KEY_LEFT
    JNE MP_RIGHT
    CMP BYTE PTR [player_x], PLAY_LEFT + 1
    JLE MP_DONE             
    
    MOV DL, [player_x]
    MOV DH, PLAY_BOT
    CALL EraseAt        
    DEC BYTE PTR [player_x]
    
    JMP MP_DONE


MP_RIGHT:
    ;ekran sonuysa saga ilerletme
    CMP AH, KEY_RIGHT
    JNE MP_DONE
    CMP BYTE PTR [player_x], PLAY_RIGHT - 1
    JGE MP_DONE              
    
    MOV DL, [player_x]
    MOV DH, PLAY_BOT
    CALL EraseAt         
    
    INC BYTE PTR [player_x]

MP_DONE:
    RET
MovePlayer ENDP


SpawnAstroid PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    
    ;astroid spawnlama sansi
    CALL GetRand
    MOV BL, ROCK_PROB
    DIV BL
    CMP AH, 0
    JNE SA_EXIT
    
    ;astroid kucuk mu buyuk mu
    CALL GetRand
    MOV BL, BIG_PROB
    DIV BL
    CMP AH, 0
    JE  TRY_BIG
    JMP TRY_SMALL

TRY_SMALL:
    MOV SI, 0
SA_S_LOOP:

    ;bos slot varsa spawnlamaya devam et
    CMP SI, MAX_SMALL
    JGE SA_EXIT
    CMP BYTE PTR [s_col+SI], 0
    JE  SA_S_OK
    INC SI
    JMP SA_S_LOOP

SA_S_OK:

    ;rastgele pozisyonda spawnla
    CALL GetRand
    MOV BL, PLAY_RIGHT-PLAY_LEFT
    DIV BL
    ADD AH, PLAY_LEFT
    MOV [s_col+SI], AH
    MOV BYTE PTR [s_row+SI], PLAY_TOP
    
    ;rastgele hiz belirle    
    CALL GetSpeed
    MOV [s_delay_max+SI], AL
    MOV [s_delay_cur+SI], AL
    JMP SA_EXIT

TRY_BIG:
    MOV SI, 0
SA_B_LOOP: 

    ;bos slot varsa spawnlamaya devam et
    CMP SI, MAX_BIG
    JGE TRY_SMALL
    CMP BYTE PTR [b_col+SI], 0
    JE  SA_B_OK
    INC SI
    JMP SA_B_LOOP

SA_B_OK:

    ;rastgele pozisyonda spawnla
    CALL GetRand
    MOV BL, PLAY_RIGHT-PLAY_LEFT-1
    DIV BL
    ADD AH, PLAY_LEFT
    MOV [b_col+SI], AH
    MOV BYTE PTR [b_row+SI], PLAY_TOP
    
    ;rastgele hiz belirle
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
SpawnAstroid ENDP



MoveAsteroids PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI


    MOV SI, 0
MA_S_LOOP:

    ;astroidin bekleme degeri kadar tick gecince haraket et
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
    
    ;astroid en altta ise slotu bosalt ve puan ekle
    CMP BYTE PTR [s_row+SI], PLAY_BOT+1
    JL  MA_S_NEXT
    MOV BYTE PTR [s_col+SI], 0
    ADD WORD PTR [score_val],1
MA_S_NEXT:
    INC SI
    JMP MA_S_LOOP


MA_B_START:

    MOV SI, 0
MA_B_LOOP:

    ;astroidin bekleme degeri kadar tick gecince haraket et
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
    
    ;astroid en altta ise slotu bosalt ve puan ekle    
    CMP BYTE PTR [b_row+SI], PLAY_BOT+1
    JL  MA_B_NEXT
    MOV BYTE PTR [b_col+SI], 0
    ADD WORD PTR [score_val],2
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



GetSpeed PROC NEAR
    ;astroidin kac tickte bir haraket edicegini belirle
    CALL GetRand
    MOV BL, 3
    DIV BL
    INC AH
    MOV AL, AH
    RET
GetSpeed ENDP


SpawnShield PROC NEAR
    PUSH AX
    PUSH BX
    
    ;kalkan yoksa ve sans tutarsa kalkan spawnla
    CMP BYTE PTR [shld_spawned], 1  
    JE  SH_EXIT                  

    CALL GetRand
    MOV BL, SHIELD_PROB            
    DIV BL
    CMP AH, 0
    JNE SH_EXIT                   

    ;rastgele pozisyonda kalkan spawnla
    CALL GetRand
    MOV BL, PLAY_RIGHT-PLAY_LEFT
    DIV BL
    ADD AH, PLAY_LEFT
    MOV [shld_col], AH
    MOV BYTE PTR [shld_row], PLAY_TOP
    MOV BYTE PTR [shld_spawned], 1

SH_EXIT:
    POP BX
    POP AX
    RET
SpawnShield ENDP



MoveShield PROC NEAR
    PUSH AX
    PUSH DX
    
    ;kalkan varsa hareket ettir
    CMP BYTE PTR [shld_spawned], 0
    JE  MS_EXIT                   
    MOV DL, [shld_col]
    MOV DH, [shld_row]
    CALL EraseAt
    INC BYTE PTR [shld_row]

    ;kalkan en altta ise slotu bosalt
    CMP BYTE PTR [shld_row], PLAY_BOT+1
    JL  MS_EXIT                    
    MOV BYTE PTR [shld_spawned], 0  

MS_EXIT:
    POP DX
    POP AX
    RET
MoveShield ENDP



CheckCollisions PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV AL, [player_x]
    MOV BL, PLAY_BOT
    

    MOV SI, 0
CC_S:
    ;kucuk astroid oyuncuyla ayni yerde mi
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

    MOV SI, 0  
    
CC_B_LOOP:
    ;buyuk astroid oyuncuyla ayni yerde mi
    CMP SI, MAX_BIG
    JGE CC_SHLD
    CMP BYTE PTR [b_col+SI], 0
    JE  CC_B_N
    CMP [b_row+SI], BL
    JNE CC_B_N
    MOV CL, [b_col+SI]
    CMP AL, CL
    JE  HIT_B  
    ;buyuk astroiding ikinci parcasi
    INC CL
    CMP AL, CL
    JE  HIT_B 
    
CC_B_N:
    INC SI
    JMP CC_B_LOOP

HIT_B:
    MOV BYTE PTR [b_col+SI], 0
    DEC BYTE PTR [player_lives]

CC_CHECK_DEAD:
    CMP BYTE PTR [player_lives], 0
    JG  CC_SHLD
    MOV BYTE PTR [player_dead], 1

CC_SHLD:
    ;kalkan varsa oyuncuyla ayni yerde mi
    CMP BYTE PTR [shld_spawned], 0
    JE  CC_DONE
    CMP [shld_row], BL
    JNE CC_DONE
    MOV CL, [shld_col]
    CMP AL, CL
    JNE CC_DONE
    MOV BYTE PTR [shld_spawned], 0
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

    ; oyuncu
    MOV DH, PLAY_BOT
    MOV DL, [player_x]
    MOV AL, '^'
    MOV BL, CLR_PLAYER
    CALL PrintChar

    ; kucuk astroid
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
    ; buyuk astroid
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
    ;kalkan
    CMP BYTE PTR [shld_spawned], 0
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



DrawHUD PROC NEAR 

    ;baslik
    MOV DH, 0
    MOV DL, 0
    MOV BL, CLR_TEXT
    LEA SI, msg_title
    CALL PrintStr

    ;can
    MOV DH, 1
    MOV DL, 1
    MOV BL, CLR_TEXT
    LEA SI, msg_lives
    CALL PrintStr
    MOV AL, [player_lives]
    ADD AL, '0'
    MOV BL, CLR_SHIELD 
    CALL PrintChar

    ;skor
    MOV DH, 1
    MOV DL, 10
    MOV BL, CLR_TEXT
    LEA SI, msg_score
    CALL PrintStr       

    ;skor degeri
    MOV DH, 1
    MOV DL, 16
    CALL SetCursor     
    LEA SI, score_buf
    MOV BL, CLR_PLAYER        
    CALL PrintStr
    RET
DrawHUD ENDP

END START