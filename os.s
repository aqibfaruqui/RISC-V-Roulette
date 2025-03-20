;-----------------------------------------------------
;       Ex5: Counters and Timers
;       Aqib Faruqui 
;       Version 5.4
;       18th March 2025
;
; This programme emulates a stopwatch using the
; on-board timer and LCD with buttons to start,
; pause and reset.
;
;
; Last modified: 14/03/2025
;
; Known bugs: _
;
; Current task: Running 1 second timer
;
; Questions: 
;       1. Bad practice to write in whole byte for RS from user mode
;       2. Use a2 for delay or push/pop function parameter
;       3. Where to LW lcd_port for clear screen ECALL
;       4. Where to keep count if used in function argument/returns but also used across whole programme
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
                        DEFW    indefButton
                        DEFW    timedButton
                        DEFW    secondTimer



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
;          param: s0 = System Call argument
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
indefButton:    LW   s0, led_port               ; Load LED port
        
        indefStart:     LBU  t0, 1[s0]                  ; Read button inputs
                        BNE  t0, a0, start              ; Wait for SW1 button press
                
                RET


;-----------------------------------------------------
;       Function: ECALL 3
;                 Waits momentarily for button press
;          param: a0 = Button Number (0x01 -> SW1, 0x02 -> SW2, 0x04 -> SW3, 0x08 -> SW4)
;         return: a0 = 0 if button pressed, unchanged if not
;-----------------------------------------------------
timedButton:    LW   s0, led_port               ; Load LED port
                LI   t0, 0x003D0900             ; Initialise time counter (0.1 seconds)

        timedStart:     LBU  t1, 1[s0]                  ; Read button inputs
                        BEQ  t1, a0, timedPress         ; Wait for SW1 button press
                        ADDI t0, t0, -1                 ; Decrement time counter
                        BEQ  t0, zero, timedExit        ; Exit loop after time limit hit

        timedPress:     SUB  a0, a0, a0                 ; a0 = 0 for successful button press

        timedExit:      RET


;-----------------------------------------------------
;       Function: ECALL 4
;                 _
;          param: _
;         return: _
;-----------------------------------------------------
secondTimer:    LW   s0, timer_port
                LI   t0, 0x000F4240
                SW   t0, 4[s0]                  ; Set limit to 1 second
                LI   t0, 0x00000003
                SW   t0, 20[s0]                 ; Turn on counter enable and modulus control bits

        wait:           LW   t0, 12[s0]                 ; Load status register
                        BGEZ t0, wait                   ; Wait for sticky bit to set

                LI   t0, 0x80000003
                SW   t0, 16[s0]                 ; Clear status bits
                RET


; ================================= Machine Stack Space ================================ 

ORG 0x0000_0500
DEFS 0x200
machine_stack:


; ====================================== User Space ====================================

ORG 0x0004_0000
user: J main

        dec_table	DEFW	1000000000, 100000000, 10000000, 1000000
	        	DEFW	100000, 10000, 1000, 100, 10, 1

;-----------------------------------------------------
;       Function: Converts unsigned binary to Binary Coded Decimal (BCD)
;          param: a0 = Unsigned binary value 
;         return: a0 = Binary Coded Decimal (BCD) value
;-----------------------------------------------------
binaryToBCD:    LA   t0, dec_table
                MV   t1, zero
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
;       Function: Prints 4 digit hex integer to LCD
;          param: a0 = 4 digit number in BCD
;         return: _
;-----------------------------------------------------
printHex:       ADDI sp, sp, -4
                SW   ra, [sp]

                MV   s0, a0
                SRLI a0, a0, 12
                JAL printHex4
                MV   a0, s0
                SRLI a0, a0, 8
                JAL printHex4
                MV   a0, s0
                SRLI a0, a0, 4
                JAL printHex4
                MV   a0, s0
                JAL printHex4
                J printHexExit

        printHex4:      ANDI a0, a0, 0x000F
                        ADDI a0, a0, 0x30
                        MV   a1, a0
                        LI   a0, 0b00001010
                        LI   a7, 0
                        ECALL
                        RET

        printHexExit:   MV   a0, s0
                        LW   ra, [sp]
                        ADDI sp, sp, 4
                        RET

;-----------------------------------------------------
;       Function: Increments 4 digit BCD value
;          param: a0 = 4 digit number in BCD
;         return: a0 = Input + 1 adjusted for BCD
;-----------------------------------------------------
increment:      ADDI a0, a0, 1                          ; Increment input
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
;-----------------------------------------------------;

main:           
                ; 1.  Clear screen
                LI   a0, 0b00001000
                LI   a1, 0x01
                LI   a7, 0                      ; writeLCD ECALL -> Clear screen
                ECALL                           

                ; 2. Print start value
                LI   a0, 0
                CALL printHex
                MV   s0, a0

                ; 3. Wait for start button
                LI   a0, 0x01
                LI   a7, 2
                ECALL

        increment:      ; 4. While pause not pressed
                        LI   a0, 0x02
                        LI   a7, 3
                        ECALL
                        BEZ  a0, zero, pause

                        ; 5. 1 second timer
                        LI   a7, 4
                        ECALL

                        ; 6. Increment counter
                        MV   a0, s0
                        CALL increment
                        MV   s0, a0
                        LI   a0, 0b00001000
                        LI   a1, 0x01
                        LI   a7, 0                      ; writeLCD ECALL -> Clear screen
                        ECALL
                        MV   a0, s0
                        CALL printHex

                        B increment

        pause:          ; 7. Wait for reset


stop:   J    stop

; =================================== User Stack Space ================================= 

ORG 0x0004_0500
DEFS 0x200
user_stack:

; ======================================= Strings ====================================== 

org 0x0004_0700
counter DEFH    0b0000_0000_0000_0000