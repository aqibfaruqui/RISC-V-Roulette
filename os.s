;-----------------------------------------------------
;       Ex5: Counters and Timers
;       Aqib Faruqui 
;       Version 1.1
;       10th March 2025
;
; This programme emulates a stopwatch using the
; on-board timer and LCD with buttons to start,
; pause and reset.
;
;
; Last modified: 12/03/2025
;
; Known bugs: writeString overwrites a0 -> change to t registers
;
; Questions: 
;       1. Bad practice to write in whole byte for RS from user mode
;       2. Use a2 for delay or push/pop function parameter
;       3. Where to LW lcd_port for clear screen ECALL
;
;-----------------------------------------------------

; ================================== Initialisation ===================================

        ORG 0
        J machine
        
        lcd_port                DEFW    0x0001_0100


; ==================================== Trap Table =====================================

        trap            DEFW    0x0000_0000     
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000    
                        DEFW    0x0000_0000
                        DEFW    ecallHandler            


; ================================= ECALL Jump Table ==================================

        jump            DEFW    writeLCD
                        DEFW    writeString            


; =================================== Machine Space ===================================

machine:
        LA   sp, machine_stack

        LI   t0, 0x0000_1800            
        CSRC MSTATUS, t0                ; Set previous priority mode to user
        LA   t0, mhandler
        CSRW MTVEC, t0                  ; Initialise trap handler address
        CSRW MSCRATCH, sp               ; Save machine stack pointer
        LA   sp, user_stack             
        LA   ra, user
        CSRW MEPC, ra                   ; Set user space address
        MRET                            ; Jump to user mode


;-----> Function: Trap handler
;          param: s0 = System Call argument
;         return: _
mhandler:
        CSRRW sp, MSCRATCH, sp          ; Save user sp, get machine sp
        ADDI  sp, sp, -8                ;
        SW    s0, 4[sp]                 ; Push working registers onto machine stack
        SW    ra, [sp]                  ;
        CSRR  t1, MCAUSE                ; Find trap cause (e.g. ECALL = 8)
        LA    t0, trap                  ; Point to trap jump table
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

;-----> Function: ECALL handler
;          param: a7 = ECALL number
;         return: _
ecallHandler:
        ADDI sp, sp, -4
        SW   ra, [sp]

        LA   t0, jump                   ; Point to ECALL jump table
        SLLI a7, a7, 2                  ; Multiply ECALL index by 4 to index words
        ADD  t0, t0, a7                 ; Calculate table entry address
        LW   t0, [t0]                   ; Load target address
        LA   ra, ecallHandler_exit      ; Store return address 
        JR   t0                         ; Jump

        ecallHandler_exit:
        LW   ra, [sp]
        ADDI sp, sp, 4
        RET

delay:  ADDI a2, a2, -1
        BNE  zero, a2, delay
        RET

;-----> Function: Writes command or character to LCD
;          param: a0 = Control(0)/Data(1) a1 = Character ASCII
;         return: _
writeLCD:
        ADDI sp, sp, -4
        SW   ra, [sp]

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

;-----> Function: Calls writeLCD on each character of a string
;          param: a1 = String Pointer
;         return: _
writeString:
        ADDI sp, sp, -8                 ; 1. Push working registers
        SW   a1, 4[sp]                  ;      - Push string pointer
        SW   ra, [sp]                   ;      - Push return address
        MV   s0, a1                     ; 2. Move pointer to local register
        LW   s1, lcd_port
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

; ================================= Machine Stack Space ================================ 

ORG 0x0000_0500
DEFS 0x200
machine_stack:


; ====================================== User Space ====================================

ORG 0x0004_0000
user:

        LI   a0, 0b00001000
        LI   a1, 0x01
        LI   a7, 0                      ; writeLCD ECALL -> Clear screen
        ECALL                           

        LI   a0, 0b00001010
        LI   a1, string
        LI   a7, 1                      ; writeString ECALL
        ECALL                           

stop:   J    stop

; =================================== User Stack Space ================================= 

ORG 0x0004_0500
DEFS 0x200
user_stack:

; ======================================= Strings ====================================== 

org 0x0004_0700
string  DEFB    "Hello World!\0"