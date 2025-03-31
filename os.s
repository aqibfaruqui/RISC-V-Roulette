;-----------------------------------------------------
;       Ex5: Counters and Timers
;       Aqib Faruqui 
;       Version 5.5
;       24th March 2025
;
; This programme emulates a stopwatch using the
; on-board timer and LCD with buttons to start,
; pause and reset.
;
; Known bugs: None
;
;-----------------------------------------------------

; ================================== Initialisation ===================================

        ORG 0
        J machine
        
        led_port                DEFW    0x0001_0000
        lcd_port                DEFW    0x0001_0100
        timer_port              DEFW    0x0001_0200


; ================================== Machine Tables ====================================

        trap_table      DEFW    0x0000_0000     
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000
                        DEFW    ecallHandler            

        ecall_table     DEFW    writeLCD
                        DEFW    writeString
                        DEFW    buttonIndef
                        DEFW    buttonCheck
                        DEFW    timerStart
                        DEFW    timerCheck



; =================================== Machine Space ===================================

machine:        LA   sp, machine_stack
                LI   t0, 0x0000_1800            
                CSRC MSTATUS, t0                ; Set previous priority mode to user
                LA   t0, mhandler
                CSRW MTVEC, t0                  ; Initialise trap handler address
                CSRW MSCRATCH, sp               ; Save machine stack pointer
                LA   sp, user_stack             
                LA   ra, user
                CSRW MEPC, ra                   ; Set user space address
                MRET                            ; Jump to user mode


;-----------------------------------------------------
;       Function: Trap handler
;          param: s0 = Saved register
;         return: _
;-----------------------------------------------------
mhandler:       CSRRW sp, MSCRATCH, sp          ; Save user sp, get machine sp
                ADDI  sp, sp, -8                ;
                SW    s0, 4[sp]                 ; Push working registers onto machine stack
                SW    ra, [sp]                  ;
                CSRR  t1, MCAUSE                ; Find trap cause (e.g. ECALL = 8)
                LA    t0, trap_table            ; Point to trap jump table
                SLLI  t1, t1, 2                 ; Multiply MCAUSE by 4 to index words
                ADD   t0, t0, t1                ; Calculate table entry address
                LW    t0, [t0]                  ; Load target address
                LA    ra, mhandler_exit         ; Store return address
                JR    t0                        ; Jump

                mhandler_exit:
                CSRRW t0, MEPC, t0
                ADDI  t0, t0, 4
                CSRRW t0, MEPC, t0              ; Correcting MEPC return address to next instruction
                LW   ra, [sp]                   ;
                LW   s0, 4[sp]                  ; Pop working registers from machine stack
                ADDI sp, sp, 8                  ;
                CSRRW sp, MSCRATCH, sp          ; Save machine sp, get user sp
                MRET


;-----------------------------------------------------
;       Function: ECALL handler
;          param: a7 = ECALL number
;         return: _
;-----------------------------------------------------
ecallHandler:   ADDI sp, sp, -4
                SW   ra, [sp]

                LA   t0, ecall_table            ; Point to ECALL jump table
                SLLI a7, a7, 2                  ; Multiply ECALL index by 4 to index words
                ADD  t0, t0, a7                 ; Calculate table entry address
                LW   t0, [t0]                   ; Load target address
                LA   ra, ecallHandler_exit      ; Store return address 
                JR   t0                         ; Jump

                ecallHandler_exit:
                LW   ra, [sp]
                ADDI sp, sp, 4
                RET


;-----------------------------------------------------
;       Function: Delay
;          param: a2 = Delay count
;         return: _
;-----------------------------------------------------
delay:  ADDI a2, a2, -1
        BNE  zero, a2, delay
        RET


;-----------------------------------------------------
;       Function: ECALL 0
;                 Writes command or character to LCD
;          param: a0 = Control(0)/Data(1) a1 = Character ASCII
;         return: _
;-----------------------------------------------------
writeLCD:       ADDI sp, sp, -4
                SW   ra, [sp]

                LW   s1, lcd_port

                ; Step 1: Set data bus direction to read LCD controller
                LI   t0, 0b00001001
                SB   t0, 1[s1]

                ; Step 2: Enable data bus
                idle    XORI t0, t0, 0b00000100
                        SB   t0, 1[s1]             

                        ; Step 2a: Delay to stretch pulse width (min 20 cycles)
                        LI   a2, 20
                        JAL  delay

                        ; Step 3: Read LCD status byte into t1
                        LBU  t1, [s1]
                        ANDI t1, t1, 0b10000000

                        ; Step 4: Disable data bus
                        XORI t0, t0, 0b00000100
                        SB   t0, 1[s1] 

                        ; Step 5: Delay to separate enable pulses (min 48 cycles)
                        LI   a2, 48
                        JAL  delay

                        ; Step 6: Idle for longer if status byte was high
                        BNEZ t1, idle

                ; Step 7: Set data bus direction and RS to write control/data byte to LCD
                SB   a0, 1[s1]

                ; Step 8: Output parameter byte onto data bus
                SB   a1, [s1]

                ; Step 9: Enable data bus
                XORI a0, a0, 0b00000100
                SB   a0, 1[s1]

                ; Step 9a: Delay to streth pulse width (min 20 cycles)
                LI   a2, 20
                JAL delay

                ; Step 10: Disable data bus
                XORI a0, a0, 0b00000100
                SB   a0, 1[s1]

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET


;-----------------------------------------------------
;       Function: ECALL 1
;                 Calls writeLCD on each character of a string
;          param: a1 = String Pointer
;         return: _
;-----------------------------------------------------
writeString:    ADDI sp, sp, -8                 ; 1. Push working registers
                SW   a1, 4[sp]                  ;      - Push string pointer
                SW   ra, [sp]                   ;      - Push return address
                MV   s0, a1                     ; 2. Move pointer to local register
                J    writeStr1

                writeStrLoop:
                        CALL writeLCD                  
                        ADDI s0, s0, 1                  ; Increment string pointer

                writeStr1:
                        LB   a1, [s0]                   ; Load next character
                        BNEZ a1, writeStrLoop           ; Write char if string pointer not at \0

                        LW   ra, [sp]
                        LW   a1, 4[sp]
                        ADDI sp, sp, 8
                        RET


;-----------------------------------------------------
;       Function: ECALL 2
;                 Waits indefinitely for button press
;          param: a0 = Button Number (0x01 -> SW1, 0x02 -> SW2, 0x04 -> SW3, 0x08 -> SW4)
;         return: _
;-----------------------------------------------------
buttonIndef:    LW   s0, led_port               ; Load LED port
        
        indefStart:     LBU  t0, 1[s0]                  ; Read button inputs
                        BNE  t0, a0, indefStart         ; Wait for button press
                
                RET


;-----------------------------------------------------
;       Function: ECALL 3
;                 Checks for button press
;          param: a0 = Button Number (0x01 -> SW1, 0x02 -> SW2, 0x04 -> SW3, 0x08 -> SW4)
;         return: a0 = 0 if button pressed, unchanged if not
;-----------------------------------------------------
buttonCheck:    LW   s0, led_port               ; Load LED port
                LBU  t0, 1[s0]                  ; Read button inputs
                BNE  t0, a0, buttonExit         ; Check button press

                SUB  a0, a0, a0                 ; a0 = 0 for successful button press

        buttonExit:     RET


;-----------------------------------------------------
;       Function: ECALL 4
;                 Starts 1 second timer
;          param: _
;         return: _
;-----------------------------------------------------
timerStart:     LW   s0, timer_port
                LI   t0, 0x000F4240
                SW   t0, 4[s0]                  ; Set limit to 1 second
                LI   t0, 0x00000003
                SW   t0, 20[s0]                 ; Turn on counter enable and modulus control bits
                RET


;-----------------------------------------------------
;       Function: ECALL 5
;                 Checks timer completion
;          param: _
;         return: a0 = 0 if timer complete, 1 otherwise
;-----------------------------------------------------
timerCheck:     LW   s0, timer_port
                LW   t0, 12[s0]                 ; Load status register
                LI   a0, 1                      ; a0 = 1 maintained if timer incomplete
                BGEZ t0, timerExit              ; Check if sticky bit set

                LI   t0, 0x80000000
                SW   t0, 16[s0]                 ; Clear sticky bit
                LI   a0, 0                      ; a0 = 0 if timer complete
                
        timerExit:      RET


; ================================= Machine Stack Space ================================

ORG 0x0000_0500
DEFS 0x200
machine_stack:


; ====================================== User Space ====================================

ORG 0x0004_0000
user: J main

;-----------------------------------------------------
;       Function: Prints 4 digit hex integer to LCD
;          param: a0 = 4 digit number in BCD
;         return: _
;-----------------------------------------------------
printHex:       ADDI sp, sp, -4
                SW   ra, [sp]

                MV   s0, a0                             ; Save input
                SRLI a0, a0, 12                         ; Shift first digit into range
                JAL printHex4                           ; Print first digit
                
                MV   a0, s0                             ; Restore saved input
                SRLI a0, a0, 8                          ; Shift second digit into range
                JAL printHex4                           ; Print second digit

                MV   a0, s0                             ; Restore saved input
                SRLI a0, a0, 4                          ; Shift third digit into range
                JAL printHex4                           ; Print third digit

                MV   a0, s0                             ; Restore saved input
                JAL printHex4                           ; Print fourth digit (already in range)
                J printHexExit

        printHex4:      ANDI a0, a0, 0x000F                     ; Clear all bits except bottom 4
                        ADDI a0, a0, 0x30                       ; Add '0' to convert to ASCII
                        MV   a1, a0
                        LI   a0, 0b00001010                     
                        LI   a7, 0                              ; ECALL 0 prints to LCD
                        ECALL
                        RET

        printHexExit:   MV   a0, s0                             ; Restore caller state
                        LW   ra, [sp]
                        ADDI sp, sp, 4
                        RET

;-----------------------------------------------------
;       Function: Increments 4 digit BCD value, 9999 loops back to 0000
;          param: a0 = 4 digit number in BCD
;         return: a0 = Input + 1 adjusted for BCD
;-----------------------------------------------------
incrementBCD:   ADDI a0, a0, 1                          ; Increment input
                LI   t0, 0b0000_0000_0000_1010          ; 10 = Mask for overflowing BCD digit (>9)
                AND  t1, a0, t0                         ; Check for overflowing least significant digit
                LI   t2, 0                              ; Initialise propagation counter (used to restore shifted value later)
                BNE  t0, t1, postpropagate              ; Propagate carry to next digit
        
        propagate:      ADDI t2, t2, 4                          ; Increment propagation counter (adjusted for bits shifted)
                        ADDI a0, a0, 6                          ; Add 6 to propagate carry
                        SRLI a0, a0, 4                          ; Shift away lowest digit
                        AND  t1, a0, t0                         ; Check for overflowing next digit
                        BEQ  t0, t1, propagate                  ; Propagate carry again

        postpropagate:  SLL  a0, a0, t2                         ; Restore propagation right shifts
                        RET

;-----------------------------------------------------;
;                                                     ;
;                    Main programme                   ;
;                                                     ; 
;                   SW1             SW2               ;
;         -->{Start}---->{Increment}--->{Pause}       ;
;             ^                            |          ;
;             |____________________________|          ;
;                           SW3                       ;
;                                                     ;
;-----------------------------------------------------;

main:           LI   a0, 0b00001000                     ; Setting LCD to write control byte 
                LI   a1, 0x01                           ; Clear screen control byte
                LI   a7, 0                              ; ECALL 0 clears screen
                ECALL                           

        start:          LI   a0, 0                              ; Initialise counter
                        CALL printHex                           ; Print starting 0
                        MV   s0, a0                             ; Save counter in s0
                        LI   a0, 0x01                           ; Load button SW1 (start button)
                        LI   a7, 2                              ; ECALL 2 waits indefinitely for button press
                        ECALL

        increment:      LI   a7, 4                              ; ECALL 4 starts timer
                        ECALL

                timerWait:      LI   a0, 0x02                           ; Load button SW2 (pause button)
                                LI   a7, 3                              ; ECALL 3 checks button press and returns
                                ECALL
                                BEQZ a0, pause                          ; If SW2 pressed, move to pause state
                                LI   a7, 5                              ; ECALL 5 checks timer completion
                                ECALL
                                BNEZ a0, timerWait                      ; Continue to check pause and timer completion until timer complete

                        MV   a0, s0                             ; Load counter
                        CALL incrementBCD                       ; Increment counter
                        MV   s0, a0                             ; Save counter
                        LI   a0, 0b00001000
                        LI   a1, 0x01
                        LI   a7, 0                              ; ECALL 0 clears screen
                        ECALL
                        MV   a0, s0                             ; Load counter
                        CALL printHex                           ; Print 4 digit counter 
                        
                        J increment                             ; Loop back to start of increment state

        pause:          LI   a0, 0x04                           ; Load button SW3 (reset button)
                        LI   a7, 2                              ; ECALL 2 waits indefinitely for button press
                        ECALL

                J main                                  ; Reset button press restarts main loop

stop:   J    stop

; =================================== User Stack Space ================================= 

ORG 0x0004_0500
DEFS 0x200
user_stack: