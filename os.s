;-----------------------------------------------------
;       Ex7: Key Debouncing and Keyboard Scanning
;       Aqib Faruqui 
;       Version 7.8
;       3rd April 2025
;
; This programme ...
;
; Known bugs: FIX DEBOUNCE KEYPAD STATE WRITE BACK
;
; Questions: 
;       1. Use a2 for delay or push/pop function parameter
;       3. Use CSRW or CSRS in setting CSR register bits
;       4. Better to separately clear and set two bits or write both at same time in LCD
;       5. Delay calculations
;       7. PIO_DIR[s0] or PIO_BASE + PIO_DIR
;       8. Unrolled loop in ISR?
;       9. Use SLTU for setting 0 (success) / 1 (fail) function returns
;       10. Remove PIO_DIR from interrupt and do once in timer start? for speed
;       11. Use SLLI/SRLI t0, 1 or ADD/SUB t0, t0, t0 in ISR
;       12. ECALL or function call from ISR
;               - so should function call (ECALL) stack all registers it uses?
;       13. !!! stack t0/t1 in writeLCD or from caller in timer_isr or use s1/s2...
;
;-----------------------------------------------------

; ================================== Initialisation ===================================

        INCLUDE ../utils/header.s
        ORG 0
        J initialisation

; ================================== Machine Tables ====================================

        exception_table         DEFW    0x0000_0000     
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000
                                DEFW    ecallHandler    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000       
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000         

        interrupt_table         DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000    
                                DEFW    0x0000_0000  
                                DEFW    0x0000_0000  
                                DEFW    mExtIntHandler    

        ecall_table             DEFW    writeLCD
                                DEFW    timerStart
                                DEFW    timerCheck

       mExtInt_table            DEFW    0x0000_0000
                                DEFW    0x0000_0000
                                DEFW    0x0000_0000
                                DEFW    0x0000_0000
                                DEFW    timerISR
                                DEFW    0x0000_0000


; =================================== Machine Space ===================================

initialisation: LA   sp, machine_stack
                LI   t0, 0x0000_1800            ; Load MPP[1:0] mask (previous priority)
                CSRC MSTATUS, t0                ; Set previous priority mode to user (Clearing MPP[1:0])
                LI   t0, 0x80                   ; Load MPIE bit (bit 7)
                CSRW MSTATUS, t0                ; Set previous MIE to enable interrupts
                LA   t0, mhandler               
                CSRW MTVEC, t0                  ; Initialise trap handler address
                CSRW MSCRATCH, sp               ; Save machine stack pointer
                LA   sp, user_stack             ; Load user stack pointer
                LA   ra, user                   ; Load user space base address 
                CSRW MEPC, ra                   ; Set previous PC to user space

                LI   t0, INTERRUPT_BASE         ; Load interrupt controller base address
                LI   t1, 0x10                   ; Timer interrupt (bit 4)
                SW   t1, INTERRUPT_ENABLES[t0]  ; Enable timer interrupts
                LI   t1, 0                      ; Timer to level sensitive mode
                SW   t1, INTERRUPT_MODE[t0]     ; Set mode in interrupt controller
                LI   t0, 0x800                  ; Load machine external interrupt bit (bit 11)
                CSRW MIE, t0                    ; Enable machine external interrupts in MIE

                ; MRET will:
                ; - Set PC = MEPC (user mode)
                ; - SET MSTATUS MIE bit = MPIE (1)
                ; - Set privilege mode = MPP (user mode)

                MRET                            


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
                BGEZ  t1, exceptions            ; Branch if trap is an exception, otherwise an interrupt
                ANDI  t1, t1, 0x000F            ; Clear upper bits (needed?)

        interrupts:     LA    t0, interrupt_table       ; Point to interrupt jump table
                        SLLI  t1, t1, 2                 ; Multiply MCAUSE by 4 to index words
                        ADD   t0, t0, t1                ; Calculate interrupt table entry address
                        LW    t0, [t0]                  ; Load target address
                        LA    ra, interrupt_exit        ; Store return address
                        JR    t0                        ; Jump

        exceptions:     LA    t0, exception_table       ; Point to exception jump table
                        SLLI  t1, t1, 2                 ; Multiply MCAUSE by 4 to index words
                        ADD   t0, t0, t1                ; Calculate exception table entry address
                        LW    t0, [t0]                  ; Load target address
                        LA    ra, exception_exit        ; Store return address
                        JR    t0                        ; Jump

                exception_exit: CSRRW t0, MEPC, t0              ;
                                ADDI  t0, t0, 4                 ; Move MEPC to next instruction for exceptions
                                CSRRW t0, MEPC, t0              ; Ignore for interrupts 
                interrupt_exit: LW   ra, [sp]                   ;
                                LW   s0, 4[sp]                  ; Pop working registers from machine stack
                                ADDI sp, sp, 8                  ;
                                CSRRW sp, MSCRATCH, sp          ; Save machine sp, get user sp
                                MRET


;-----------------------------------------------------
;       Function: ECALL handler
;          param: a7 = ECALL number
;         return: a0 = -1 for Invalid ECALL
;-----------------------------------------------------
ecallHandler:   ADDI sp, sp, -4
                SW   ra, [sp]

                LI   t0, NUM_ECALLS             ; Load number of ECALLs
                BGEU a7, t0, invalid_ecall      ; If a7 < 0 or a7 >= NUM_ECALLS, return -1

                LA   t0, ecall_table            ; Point to ECALL jump table
                SLLI t1, a7, 2                  ; Multiply ECALL index by 4 to index words
                ADD  t0, t0, t1                 ; Calculate table entry address
                LW   t0, [t0]                   ; Load target address
                LA   ra, ecall_exit             ; Store return address 
                JR   t0                         ; Jump
                J ecall_exit
        
        invalid_ecall:  LI   a0, -1                     ; Set error return value

        ecall_exit:     LW   ra, [sp]
                        ADDI sp, sp, 4
                        RET

;-----------------------------------------------------
;       Function: Delay
;          param: a1 = Delay count
;         return: _
;-----------------------------------------------------
delay:  ADDI a1, a1, -1
        BNEZ a1, delay
        RET


;-----------------------------------------------------
;       Function: ECALL 0
;                 Writes command/character to LCD
;          param: a0 = Character ASCII
;         return: _
;-----------------------------------------------------
writeLCD:       ADDI sp, sp, -4
                SW   ra, [sp]
                LI   s0, LCD_BASE               ; Load LCD base address
                
                LI   t0, 0x0000_0200            ; Load bit for RS
                SW   t0, LCD_CLEAR[s0]          ; Clear RS to read control byte (RS = 0)
                LI   t0, 0x0000_0900            ; Load bits for backlight and R/W
                SW   t0, LCD_SET[s0]            ; Set backlight and data bus direction to read LCD controller (R/W = 1)

        idle:           LI   t0, 0x0000_0400            ; Load data bus bit
                        SW   t0, LCD_SET[s0]            ; Enable data bus (E = 1)
                        LI   a1, 5                      ; Delay to stretch pulse width (min 20 cycles)
                        JAL  delay
                        
                        LBU  t1, LCD_DATA[s0]           ; Read LCD data 
                        ANDI t1, t1, 0b10000000         ; Isolate LCD status byte

                        LI   t0, 0x0000_0400            ; Load data bus bit
                        SW   t0, LCD_CLEAR[s0]          ; Disable data bus (E = 0)
                        LI   a1, 12                      ; Delay to separate enable pulses (min 48 cycles)
                        JAL  delay

                        BNEZ t1, idle                   ; Idle while status byte is low (display controller is busy)                   

                LI   t0, 0x0000_0100            ; Load bit for R/W
                SW   t0, LCD_CLEAR[s0]          ; Clear R/W bit to set data bus direction to write to LCD 
                
                LI   t0, 0x20                   ; Barrier betweeen control/data ASCII characters
                BLT  a0, t0, skipUpdateRS       ; Characters < 0x20 keep RS = 0 to write control byte
                LI   t0, 0x0000_0200            ; Load bit for RS
                SW   t0, LCD_SET[s0]            ; Characters >= 0x20 set RS = 1 to write data byte

        skipUpdateRS:   SB   a0, LCD_DATA[s0]           ; Output parameter byte onto data bus

                LI   t0, 0x0000_0400            ; Load data bus bit
                SW   t0, LCD_SET[s0]            ; Enable data bus (E = 1)
                LI   a1, 20                     ; Delay to stretch pulse width (min 20 cycles)
                JAL delay
                
                LI   t0, 0x0000_0400            ; Load data bus bit
                SW   t0, LCD_CLEAR[s0]          ; Disable data bus (E = 0)

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET


;-----------------------------------------------------
;       Function: ECALL 1
;                 Starts 1 second timer
;          param: _
;         return: _
;-----------------------------------------------------
timerStart:     LI   s0, TIMER_BASE
                LI   t0, 1000
                SW   t0, TIMER_LIMIT[s0]        ; Set limit to 1ms
                LI   t0, 0x00000000B
                SW   t0, TIMER_SET[s0]          ; Turn on counter enable, modulus and interrupt control bits
                RET


;-----------------------------------------------------
;       Function: ECALL 2
;                 Checks timer completion
;          param: _
;         return: a0 = 0 if timer complete, 1 otherwise
;-----------------------------------------------------
timerCheck:     LI   s0, TIMER_BASE
                LW   t0, TIMER_STATUS[s0]       ; Load status register
                LI   a0, 1                      ; Maintained if timer incomplete
                BGEZ t0, timerExit              ; Check if sticky bit set

                LI   t0, 0x80000000
                SW   t0, TIMER_CLEAR[s0]        ; Clear sticky bit
                LI   a0, 0                      ; Timer complete
                
        timerExit:      RET
                

;-----------------------------------------------------
;       Function: Machine External Interrupt Handler
;          param: _
;         return: _
;-----------------------------------------------------
mExtIntHandler: ADDI sp, sp, -4
                SW   ra, [sp]

                LI   s0, INTERRUPT_BASE
                LW   t0, INTERRUPT_REQUESTS[s0]         ; Read requests (input state of enabled interrupts)
                        LI   t1, 0                      ; Initialise counter to find interrupt request
        request_loop:   SRLI t0, t0, 1                  ; Shift request bits right until interrupt found
                        ADDI t1, t1, 1                  ; Increment interrupt request counter
                        BNEZ t0, request_loop           ; Loop until interrupt request found
                        ADDI t1, t1, -1                 ; Restore interrupt request overshoot

                LA   t0, mExtInt_table          ; Point to Machine External Interrupt jump table
                SLLI t1, t1, 2                  ; Multiply index by 4 to index words
                ADD  t0, t0, t1                 ; Calculate table entry address
                LW   t0, [t0]                   ; Load target address
                JALR t0                         ; Jump

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET
                
;-----------------------------------------------------
;       Function: Scan and debounce keypad 
;          param: _
;         return: _
;-----------------------------------------------------
keypad_lookup:  DEFB    '#', '9', '6', '3'
                DEFB    '0', '8', '5', '2'
                DEFB    '*', '7', '4', '1' 

keypad_state:   DEFB    0, 0, 0, 0
                DEFB    0, 0, 0, 0
                DEFB    0, 0, 0, 0

printChar:      ADDI sp, sp, -4
                SW   ra, [sp]
                
                LBU a0, [t3]
                CALL writeLCD

                LW   ra, [sp]
                ADDI sp, sp, 4

timerISR:       ADDI sp, sp, -4
                SW   ra, [sp]
                
                LI   s0, PIO_BASE
                LI   t0, 0xFFFF_F8FF            ; Row bits (8-10) low, rest high
                SW   t0, PIO_DIR[s0]            ; Set row bits direction to output
                
                LI   s1, 2                      ; Loop counter (int i = 2; i >= 0; i++)
                LI   s2, 0x0000_0100            ; Bit 8 (first row of keypad)

        rowLoop:        SW   s2, PIO_SET[s0]            ; Activate current row
                        NOP
                        NOP
                        LW   t2, PIO_DATA[s0]           ; Read keypad state at current row 
                        LI   t3, 0x0000_F000            ; Column bits (12-15) mask
                        AND  t2, t2, t3                 ; Isolate column bits
                        SRLI t2, t2, 12                 ; Shift column bits down to bits 0-3

        unrolledColLoop:        LA   t3, keypad_lookup          ; Pointer to keypad ASCII lookup table
                                LA   t4, keypad_state           ; Pointer to keypad rolling state 

                                ; FIRST COLUMN
                                SLLI t5, s1, 2                  ; Multiply loop counter by 4 to index table row
                                ADD  t3, t3, t5                 ; Apply row offset to keypad_lookup base
                                ADD  t4, t4, t5                 ; Apply row offset to keypad_state base

                                LBU  t5, [t4]                   ; Read current key state
                                XORI t6, t5, 0x7F               ; Toggle all but most significant bit
                                BNEZ t6, skipTo2                ; Skip print routine if key state is not ready (given next input)                
                                ANDI t6, t2, 1                  ; Check if current key (row, col) is pressed
                                LI   a0, 1                      ; Compare against current key press status
                                BNE  t6, a0, skipTo2            ; Skip print routine if last 1 needed for FF key state is not set
                                LBU  a0, [t3]                   ; Else, load relevant character
                                CALL writeLCD                   ;       and print to LCD

                skipTo2:        SLLI t5, t5, 1                  ; Shift rolling key state to make room to update 
                                ANDI t6, t2, 1
                                ADD  t5, t5, t6                 ; Update rolling key state with 0/1 in LSB
                                SB   t5, [t4]                   ; Write back key state
                                
                                ; SECOND COLUMN
                                SRLI t2, t2, 1                  ; Iterate to 2nd column
                                ADDI t3, t3, 1                  ; Increment keypad ASCII lookup table pointer
                                ADDI t4, t4, 1                  ; Increment keypad rolling state pointer

                                LBU  t5, [t4]                   ; Read current key state
                                XORI t6, t5, 0x7F               ; Toggle all but most significant bit
                                BNEZ t6, skipTo3                ; Skip print routine if key state is not ready (given next input)                
                                ANDI t6, t2, 1                  ; Check if current key (row, col) is pressed
                                LI   a0, 1                      ; Compare against current key press status
                                BNE  t6, a0, skipTo3            ; Skip print routine if last 1 needed for FF key state is not set
                                LBU  a0, [t3]                   ; Else, load relevant character
                                CALL writeLCD                   ;       and print to LCD

                skipTo3:        SLLI t5, t5, 1                  ; Shift rolling key state to make room to update 
                                ANDI t6, t2, 1
                                ADD  t5, t5, t6                 ; Update rolling key state with 0/1 in LSB
                                SB   t5, [t4]                   ; Write back key state

                                ; THIRD COLUMN
                                SRLI t2, t2, 1                  ; Iterate to 3rd column
                                ADDI t3, t3, 1                  ; Increment keypad ASCII lookup table pointer
                                ADDI t4, t4, 1                  ; Increment keypad rolling state pointer

                                LBU  t5, [t4]                   ; Read current key state
                                XORI t6, t5, 0x7F               ; Toggle all but most significant bit
                                BNEZ t6, skipTo4                ; Skip print routine if key state is not ready (given next input)                
                                ANDI t6, t2, 1                  ; Check if current key (row, col) is pressed
                                LI   a0, 1                      ; Compare against current key press status
                                BNE  t6, a0, skipTo4            ; Skip print routine if last 1 needed for FF key state is not set
                                LBU  a0, [t3]                   ; Else, load relevant character
                                CALL writeLCD                   ;       and print to LCD

                skipTo4:        SLLI t5, t5, 1                  ; Shift rolling key state to make room to update 
                                ANDI t6, t2, 1
                                ADD  t5, t5, t6                 ; Update rolling key state with 0/1 in LSB
                                SB   t5, [t4]                   ; Write back key state

                                ; FOURTH COLUMN
                                SRLI t2, t2, 1                  ; Iterate to 4th column
                                ADDI t3, t3, 1                  ; Increment keypad ASCII lookup table pointer
                                ADDI t4, t4, 1                  ; Increment keypad rolling state pointer

                                LBU  t5, [t4]                   ; Read current key state
                                XORI t6, t5, 0x7F               ; Toggle all but most significant bit
                                BNEZ t6, skipToEnd              ; Skip print routine if key state is not ready (given next input)                
                                ANDI t6, t2, 1                  ; Check if current key (row, col) is pressed
                                LI   a0, 1                      ; Compare against current key press status
                                BNE  t6, a0, skipToEnd          ; Skip print routine if last 1 needed for FF key state is not set
                                LBU  a0, [t3]                   ; Else, load relevant character
                                CALL writeLCD                   ;       and print to LCD

                skipToEnd:      SLLI t5, t5, 1                  ; Shift rolling key state to make room to update 
                                ANDI t6, t2, 1
                                ADD  t5, t5, t6                 ; Update rolling key state with 0/1 in LSB
                                SB   t5, [t4]                   ; Write back key state

                        SW   s2, PIO_CLEAR[s0]          ; Inactivate current row
                        SLLI s2, s2, 1                  ; Move to scan next row
                        ADDI s1, s1, -1                 ; Decrement loop counter
                        LI   a1, 10
                        CALL delay
                        BGEZ s1, rowLoop                ; Loop to scan next row

                LI   s0, TIMER_BASE
                LI   t0, 0x80000000
                SW   t0, TIMER_CLEAR[s0]        ; Clear timer sticky bit

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET


; ================================= Machine Stack Space ================================

DEFS 0x1024
machine_stack:


; ====================================== User Space ====================================

ORG 0x0004_0000
user: J main

main:           LI   a0, 0x01                   ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL

                LI   a7, 1                      ; ECALL 1 starts 10ms timer
                ECALL

        scan:           J scan

stop:   J    stop

; =================================== User Stack Space ================================= 

DEFS 0x1024
user_stack: