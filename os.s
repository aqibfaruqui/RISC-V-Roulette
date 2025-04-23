;-----------------------------------------------------
;       Ex7: Key Debouncing and Keyboard Scanning
;       Aqib Faruqui 
;       Version 7.0
;       3rd April 2025
;
; This programme ...
;
; Known bugs: 
;
; Questions: 
;       1. Use a2 for delay or push/pop function parameter
;       2. Where to LW lcd_port for clear screen ECALL
;       3. Use CSRW or CSRS in setting CSR register bits
;       4. Better to separately clear and set two bits or write both at same time in LCD
;       5. Delay calculations
;
;-----------------------------------------------------

; ================================== Initialisation ===================================

        INCLUDE ../header.s
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
                                DEFW    extButtonCheck

       ; mExtInt_table           DEFW    


; =================================== Machine Space ===================================

initialisation: LA   sp, machine_stack
                LI   t0, 0x0000_1800            ; Load MPP[1:0] mask (previous priority)
                CSRC MSTATUS, t0                ; Set previous priority mode to user (Clearing MPP[1:0])
                LI   t0, 0x80                   ; Load MPIE bit (bit 7)
                CSRW MSTATUS, t0                ; Set previous MIE to enable interrupts 
                LA   t0, mhandler               
                CSRW MTVEC, t0                  ; Initialise trap handler address
                LI   t0, 0x0001_0400            ; Load interrupt controller base address
                LI   t1, 0x10                   ; Timer interrupt (bit 4)
                SW   t1, 4[t0]                  ; Write enable to interrupt controller
                LI   t1, 0                      ; Timer to level sensitive mode
                SW   t1, 12[t0]                 ; Set mode in interrupt controller
                CSRW MSCRATCH, sp               ; Save machine stack pointer
                LA   sp, user_stack             ; Load user stack pointer
                LA   ra, user                   ; Load user space base address 
                CSRW MEPC, ra                   ; Set previous PC to user space
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
                BGEU a7, t0, invalid_ecall      ; If a7 < 0 or a7 >= NUM_ECALLS, return

                LA   t0, ecall_table            ; Point to ECALL jump table
                SLLI t1, a7, 2                  ; Multiply ECALL index by 4 to index words
                ADD  t0, t0, t1                 ; Calculate table entry address
                LW   t0, [t0]                   ; Load target address
                LA   ra, ecall_exit             ; Store return address 
                JR   t0                         ; Jump

        invalid_ecall:  LI   a0, -1             ; Set error return value

        ecall_exit:     LW   ra, [sp]
                        ADDI sp, sp, 4
                        RET

;-----------------------------------------------------
;       Function: Machine External Interrupt Handler
;          param: _
;         return: _
;-----------------------------------------------------
mExtIntHandler: ADDI sp, sp, -4
                SW   ra, [sp]

                p J p


                LW   ra, [sp]
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
                LW   s0, LCD_BASE               ; Load LCD base address
                
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
                BLT  a0, t0, skipUpdateRS       ; Characters < 0x20 should keep RS = 0 to write control byte
                LI   t0, 0x0000_0200            ; Load bit for RS
                SW   t0, LCD_SET[s0]            ; Set RS to write data byte

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
timerStart:     LW   s0, TIMER_BASE
                LI   t0, 1000000
                SW   t0, TIMER_LIMIT[s0]        ; Set limit to 1 second
                LI   t0, 0x00000000B
                SW   t0, TIMER_SET[s0]          ; Turn on counter enable, modulus and interrupt control bits
                RET


;-----------------------------------------------------
;       Function: ECALL 2
;                 Checks timer completion
;          param: _
;         return: a0 = 0 if timer complete, 1 otherwise
;-----------------------------------------------------
timerCheck:     LW   s0, TIMER_BASE
                LW   t0, TIMER_STATUS[s0]       ; Load status register
                LI   a0, 1                      ; Maintained if timer incomplete
                BGEZ t0, timerExit              ; Check if sticky bit set

                LI   t0, 0x80000000
                SW   t0, TIMER_CLEAR[s0]        ; Clear sticky bit
                LI   a0, 0                      ; Timer complete
                
        timerExit:      RET


;-----------------------------------------------------
;       Function: ECALL 3
;                 Check button press from external keyboard
;          param: _
;         return: _
;-----------------------------------------------------
extButtonCheck: LI   s0, PIO_BASE               ; Load PIO base address
                LW   t0, PIO_DATA[s0]           ; Read PIO data register
                

; ================================= Machine Stack Space ================================

ORG 0x0000_0500
DEFS 0x1024
machine_stack:


; ====================================== User Space ====================================

ORG 0x0004_0000
user: J main

main:           LI   a0, 0b00001000                     ; Setting LCD to write control byte 
                LI   a1, 0x01                           ; Clear screen control byte
                LI   a7, 0                              ; ECALL 0 clears screen
                ECALL                           

stop:   J    stop

; =================================== User Stack Space ================================= 

ORG 0x0004_1000
DEFS 0x1024
user_stack: