;-----------------------------------------------------
;       Ex9: Roulette
;       Aqib Faruqui 
;       Version 9.8
;       1st May 2025
;
; This programme emulates a roulette board with the
; ability to bet on black/red with a starting balance
; of 100, the roulette spin mechanism relies on random
; number generation and timer interrupts. The game 
; ends when balance reaches 0. 
;
;-----------------------------------------------------

INCLUDE operatingsystem.s

; ====================================== User Space ====================================

ORG 0x0004_0000
user: J main

        ROULETTE_INCREMENT      EQU         3
        ROULETTE_SIZE           EQU         111
        LCD_CTRL_CLEAR          EQU         0x01
        LCD_CTRL_LINE1          EQU         0x80
        LCD_CTRL_LINE2          EQU         0xC0

        dec_table	DEFW	1000000000, 100000000, 10000000, 1000000
	        	DEFW	100000, 10000, 1000, 100, 10, 1

;-----------------------------------------------------
;       Function: Converts unsigned binary to Binary Coded Decimal (BCD)
;          param: a0 = Unsigned binary value 
;         return: a0 = Binary Coded Decimal (BCD) value
;-----------------------------------------------------
binaryToBCD:    LA   t0, dec_table
                LI   t1, 0
                LI   t3, 1
                J    bcdLoopIn

        bcdLoop:        DIVU t4, a0, t2
                        REMU a0, a0, t2

                        ADD  t1, t1, t4
                        SLLI t1, t1, 4

                        ADDI t0, t0, 4

        bcdLoopIn:      LW   t2, [t0]
                        BNE  t2, t3, bcdLoop

        bcdLoopOut:     ADD  a0, t1, a0
                        RET     

;-----------------------------------------------------
;       Function: Performs XorShift32 algorithm for pseudorandom number generation
;          param: a0 = Integer
;         return: a0 = Pseudorandom integer
;-----------------------------------------------------
XorShift32:     MV   t0, a0
                MV   t1, a0
                SLLI t0, t0, 13
                XOR  t0, t0, t1                 ; x ^= x << 13;
                SRLI t0, t0, 17
                XOR  t0, t0, t1                 ; x ^= x >> 17;
                SLLI t0, t0, 5
                XOR  t0, t0, t1                 ; x ^= x << 5;
                MV   a0, t0
                RET


;-----------------------------------------------------
;       Function: Updates roulette left and right pointers for rotation
;          param: _
;         return: _
;-----------------------------------------------------
rotateRoulette: LA   t0, roulette_pointer       ; Address of pointer in roulette string
                LW   t1, [t0]                   ; Load pointer
                ADDI t1, t1, ROULETTE_INCREMENT ; Add 3 to roulette pointer to move to next character
                LI   t2, ROULETTE_SIZE          ; Check for pointer of bounds
                REMU t1, t1, t2                 ; Wrap pointer back to beginning of roulette string
                SW   t1, [t0]                   ; Store new roulette pointer
                RET


;-----------------------------------------------------
;       Function: Prints current state (16 characters) of roulette
;          param: _
;         return: _
;-----------------------------------------------------
printRoulette:  ADDI sp, sp, -8
                SW   s0, 4[sp]
                SW   ra, [sp]

                LA   t0, roulette               ; Pointer to roulette string
                LW   t1, roulette_pointer       ; Current start position of roulette
                LA   t2, roulette_end           ; Roulette size for wrapping back to start of roulette
                LI   t3, 17                     ; Counter to print 16 characters
                ADD  s0, t0, t1                 ; Move pointer to local register
                J    printRlt1

        wrapRlt:        MV   s0, t0                     ; Wrap string pointer back to start
        printRltLoop:   LI   a7, 0
                        ECALL                           ; ECALL 0 prints character to LCD
                        
        printRlt1:      LB   a0, [s0]                   ; Load next character
                        ADDI s0, s0, 1                  ; Increment string pointer
                        ADDI t3, t3, -1                 ; Decrement 16 character counter
                        BGE  s0, t2, wrapRlt            ; Move string pointer to start on next iteration if out of range
                        BNEZ t3, printRltLoop           ; Write char if 16 characters not already printed

                        LW   ra, [sp]
                        LW   s0, 4[sp]
                        ADDI sp, sp, 8
                        RET


;-----------------------------------------------------
;       Function: Prints string to LCD
;          param: a0 = Pointer to string
;         return: _
;-----------------------------------------------------
printString:    ADDI sp, sp, -8
                SW   s0, 4[sp]
                SW   ra, [sp]

                MV   s0, a0                     ; Move pointer to local register
                J    printStr1

        printStrLoop:   LI   a7, 0
                        ECALL                           ; ECALL 0 prints character to LCD             
                        ADDI s0, s0, 1                  ; Increment string pointer

        printStr1:      LB   a0, [s0]                   ; Load next character
                        BNEZ a0, printStrLoop           ; Write char if string pointer not at \0

                        LW   ra, [sp]
                        LW   s0, 4[sp]
                        ADDI sp, sp, 8
                        RET


;-----------------------------------------------------
;       Function: Prints 3 digit hex integer to LCD
;          param: a0 = 3 digit number in BCD
;         return: _
;-----------------------------------------------------
printHex:       ADDI sp, sp, -8
                SW   s0, 4[sp]
                SW   ra, [sp]

                MV   s0, a0                             ; Save input
                SRLI a0, a0, 8                          ; Shift first digit into range
                JAL printHex4                           ; Print first digit
                
                MV   a0, s0                             ; Restore saved input
                SRLI a0, a0, 4                          ; Shift second digit into range
                JAL printHex4                           ; Print second digit

                MV   a0, s0                             ; Restore saved input
                JAL printHex4                           ; Print third digit (already in range)
                J printHexExit

        printHex4:      ANDI a0, a0, 0x000F                     ; Clear all bits except bottom 4
                        ADDI a0, a0, '0'                        ; Add '0' to convert to ASCII                     
                        LI   a7, 0                              ; ECALL 0 prints to LCD
                        ECALL
                        RET

        printHexExit:   MV   a0, s0                             ; Restore caller state
                        LW   ra, [sp]
                        LW   s0, 4[sp]
                        ADDI sp, sp, 8
                        RET


;-----------------------------------------------------
;       Function: Prints balance to second line of LCD
;          param: _
;         return: _
;-----------------------------------------------------
printBalance:   ADDI sp, sp, -4
                SW   ra, [sp]

                LI   a0, LCD_CTRL_LINE2                 ; Move cursor to LCD second line
                LI   a7, 0
                ECALL
                LA   a0, balance_string                 ; Load "Balance: " string                 
                CALL printString                        ; Print balance string
                LW   a0, balance                        ; Load user balance
                CALL binaryToBCD                        ; Convert balance to BCD
                CALL printHex                           ; Print balance (3 digits)

                LI   a0, LCD_CTRL_LINE1                 ; Move cursor back to LCD first line
                LI   a7, 0
                ECALL

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET

;-----------------------------------------------------
;       Function: Stall 2 seconds to show message between game states
;          param: _
;         return: _
;-----------------------------------------------------
messageDelay:   LI   t0, 20000000
        msgDelayLoop:   ADDI t0, t0, -1
                        BNEZ t0, msgDelayLoop
                RET


;-----------------------------------------------------;
;                                                     ;
;                       ROULETTE                      ;
;                                                     ;
;-----------------------------------------------------;

main:           LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL
                LA   t0, balance                ; Load address of balance
                LI   t1, 100                    ; Initialise balance of 100
                SW   t1, [t0]                   ; Store starting balance

;----------------------------------------------------
;        Start: Prints start screen message &
;               polls for start button (SW1) press
;----------------------------------------------------
start:          LA   a0, start_string           ; Pointer to start message
                CALL printString                ; Print start message to LCD
                CALL printBalance
        startButton:    LI   a0, 1
                        LI   a7, 7
                        ECALL                           ; ECALL 7 checks SW1 for start button press
                        BNEZ a0, startButton            ; Poll until button pressed
                
;----------------------------------------------------
;     placeBet: Starts timer1 to scan keypad for bet
;               input & reinputs for invalid bets
;               '*' = Backspace
;               '#' = Enter Bet
;----------------------------------------------------
                LI   a7, 3
                ECALL                           ; ECALL 3 starts 1ms timer for keypad scanning
placeBet:       LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL
                LA   a0, enter_string           ; Prompt user to enter bet
                CALL printString                ; Print "Enter bet" string
                LI   a0, LCD_CTRL_LINE2         ; Control to move cursor to line 2
                LI   a7, 0                      ; ECALL 0 repositions cursor
                ECALL
                        LI   s0, 0                      ; Initialising bet amount
                        LI   t0, 10                     ; Multiply current bet by 10 to add each new digit
                        LI   t1, 0x23                   ; ASCII for '#'
                        LI   t2, 0x2A                   ; ASCII for '*'
        getBet:         LI   a7, 1
                        ECALL                           ; ECALL 1 gets character from keypad input
                        BEQ  a0, t1, chooseColour       ; '#' finalises bet
                        BEQ  a0, t2, getBet             ; '*' does nothing
                        BLTZ a0, getBet                 ; Repeat for no character return
                        LI   a7, 0
                        ECALL                           ; Print new digit to LCD
                        MUL  s0, s0, t0                 ; Multiply current bet by 10
                        SUBI a0, a0, '0'                ; Subtract '0' from new digit to convert ASCII to number
                        ADD  s0, s0, a0                 ; Add new digit
                        J getBet                        ; Continue keypad input until '#'

        invalidBet:     LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                        LI   a7, 0                      ; ECALL 0 clears screen
                        ECALL
                        LI   a0, invalid_string         ; Pointer to invalid bet string 
                        CALL printString                ; Print to LCD
                        CALL messageDelay
                        J placeBet

;----------------------------------------------------
; chooseColour: Redirects invalid bets back to placeBet
;               & prompts user to bet red or black
;               '*' = Red
;               '#' = Black
;----------------------------------------------------
chooseColour:   LI   a0, LCD_CTRL_LINE1         ; Control to move cursor to line 1
                LI   a7, 0                      ; ECALL 0 repositions cursor
                ECALL
                LW   t0, balance                ; Load user running balance
                BLT  t0, s0, invalidBet         ; Reinput bet for insufficient balance
                BEQZ s0, invalidBet             ; Reinput bet for empty bet
                SUB  s1, t0, s0                 ; Bet value removed from balance
                LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL
                LA   a0, colour_string          ; Pointer to choose colour string
                CALL printString                ; Print to LCD

        getColour:      LI   a7, 1                            
                        ECALL                           ; ECALL 1 gets character from keypad input
                        BLTZ a0, getColour              ; Continue keypad input for no character return
                        BGT  a0, t2, getColour          ; Continue keypad input for numeric input
                        LI   s2, 0                      ; 0 for black '#'
                        BEQ  a0, t1, rouletteSpin       
                        LI   s2, 1                      ; 1 for red '*'

;----------------------------------------------------
; rouletteSpin: Generates random number in the range of
;               0.5 to 1.5 total roulette spins and 
;               consequently handles spin animation
;----------------------------------------------------
rouletteSpin:   LI   a7, 8
                ECALL                           ; ECALL 8 returns system clock (for pseudo-randomness)
                CALL XorShift32                 ; Pseudorandom algorithm on system clock
                LI   t0, 37                     ; Modulo random number by 37
                REMU a0, a0, t0                 ; Random number in range [0, 36] for 37 numbers on roulette
                ADDI s3, a0, 18                 ; Roulette spins = Random number in range [18, 54] to guarantee some spins
                LI   a7, 5
                ECALL                           ; ECALL 5 starts 0.5s timer2 for generating spin events
        getSpin:        LI   a7, 2
                        ECALL                           ; ECALL 2 pops from event queue
                        BLTZ a0, getSpin                ; Poll until event detected
                        ADDI s3, s3, -1                 ; Decrement roulette spins
                        LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                        LI   a7, 0                      ; ECALL 0 clears screen
                        ECALL
                        CALL rotateRoulette             ; Move roulette string pointer
                        CALL printRoulette              ; Print new roulette state
                        BNEZ s3, getSpin                ; Spin until roulette spins = 0
                LI   a7, 6
                ECALL                           ; ECALL 6 ends and resets timer2
                CALL messageDelay

;----------------------------------------------------
; updateBalance: Exploits roulette pointer to handle 
;                win/lose logic, prints appropriate
;                message and updates user balance.
;                Moves to next round or game over at 
;                balance = 0
;----------------------------------------------------
updateBalance:  LW   t0, roulette_pointer       ; Using roulette pointer for win/loss logic
                LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL
                BEQZ t0, green                  ; Pointer == 0 -> landed on green
                ANDI t0, t0, 1                  ; Mask everything except LSB
                BEQZ t0, black                  ; Pointer == Even -> landed on black
                J red                           ; Pointer == Odd -> landed on red

        black:          LA   a0, black_string           ; Pointer to "black"
                        CALL printString                ; Print to LCD
                        BEQZ s2, win                    ; 
                        J    lose                       ;
        red:            LA   a0, red_string             ; Pointer to "red"
                        CALL printString                ; Print to LCD
                        BEQZ s2, lose                   ;
                        J    win                        ;
        green:          LA   a0, green_string           ; Pointer to "green"
                        CALL printString                ; Print to LCD
                                                        ; Green always loses

        lose:           LA   a0, lose_string            ; Pointer to lose message
                        CALL printString                ; Print to LCD
                        LA   t0, balance                ; Pointer to user balance
                        LW   t1, [t0]                   ; Load balance to subtract bet amount for losing
                        SUB  t1, t1, s0                 ; Subtract bet amount
                        SW   t1, [t0]                   ; Save new balance
                        J nextRound

        win:            LA   a0, win_string             ; Pointer to win message
                        CALL printString                ; Print to LCD
                        LA   t0, balance                ; Pointer to user balance
                        LW   t1, [t0]                   ; Load balance to add bet amount for winning
                        ADD  t1, t1, s0                 ; Add bet amount
                        SW   t1, [t0]                   ; Save new balance

        nextRound:      CALL messageDelay               ; Show "{colour}, {win/loss}" message
                        BEQZ t1, endGame                ; End game if balance == 0
                        LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                        LI   a7, 0                      ; ECALL 0 clears screen
                        ECALL
                        LA   a0, next_string            ; Pointer to start message
                        CALL printString                ; Print start message to LCD
                        CALL printBalance
                        J startButton

;----------------------------------------------------
;      endGame: Game over! Handles restart game logic
;               with balance restored to 100
;----------------------------------------------------
endGame:        LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL
                LA   a0, end_string             ; Game over!!
                CALL printString
                CALL messageDelay
                LI   a0, LCD_CTRL_CLEAR         ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL
                LA   a0, restart_string         ; Prompt user to play again
                CALL printString
        restartButton:  LI   a0, 2
                        LI   a7, 7
                        ECALL                           ; ECALL 7 checks SW2 for start button press
                        BNEZ a0, restartButton          ; Poll until button pressed
                J main

stop:   J    stop


; ====================================== Input Data ==================================== 

balance         DEFW    100

start_string    DEFB    "SW1 Start Game\0"
ALIGN

balance_string  DEFB    "Balance: \0"
ALIGN

enter_string    DEFB    "# to Enter Bet\0"
ALIGN

next_string     DEFB    "SW1 Next Round\0"
ALIGN

invalid_string  DEFB    "Low balance\0"
ALIGN

end_string      DEFB    "Game Over!\0"
ALIGN

restart_string  DEFB    "SW2 to Restart\0"
ALIGN

colour_string   DEFB    "* = red  # = blk\0"
ALIGN

black_string    DEFB    "blk\0"
ALIGN

red_string      DEFB    "red\0"
ALIGN

green_string    DEFB    "green\0"
ALIGN

win_string      DEFB    ", you win :)\0"
ALIGN

lose_string     DEFB    ", you lose :(\0"
ALIGN

roulette_pointer        DEFW    0
roulette                DEFB    "|03|26|00|32|15|19|04|21|02|25|17|34|06|27|13|36|11|30|08|23|10|05|24|16|33|01|20|14|31|09|22|18|29|07|28|12|35"
roulette_end
ALIGN                                                                                                                                   

; =================================== User Stack Space ================================= 

DEFS 0x1024
user_stack: