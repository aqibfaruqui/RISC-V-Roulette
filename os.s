;-----------------------------------------------------
;       Ex9: Music Virtual Machine
;       Aqib Faruqui 
;       Version 9.2
;       1st May 2025
;
; This programme ...
;
; Known bugs: preserve entire state on interrupts
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

; ================================== Machine Tables ===================================
tables:
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
                                DEFW    getCharacter
                                DEFW    buttonCheck

        mExtInt_table           DEFW    0x0000_0000
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
                CSRS MSTATUS, t0                ; Set previous MIE to enable interrupts
                LA   t0, mhandler               
                CSRW MTVEC, t0                  ; Initialise trap handler address
                CSRW MSCRATCH, sp               ; Save machine stack pointer
                LA   sp, user_stack             ; Load user stack pointer
                LA   ra, user                   ; Load user space base address 
                CSRW MEPC, ra                   ; Set previous PC to user space

                LI   t0, INTERRUPT_BASE         ; Load interrupt controller base address
                LI   t1, 0x10                   ; Timer interrupt (bits 4)
                SW   t1, INTERRUPT_ENABLES[t0]  ; Enable SW1 and timer interrupts
                LI   t1, 0                      ; Timer to level sensitive mode
                SW   t1, INTERRUPT_MODE[t0]     ; Set mode in interrupt controller

                ;LI   t0, SYSTEM_BASE            ; Load system controller base address
                ;LI   t1, 0xC0                   ; Buzzer Bits (bits 6-7)
                ;SW   t1, SYSTEM_PINS[t0]        ; Redirect PIO pins to buzzer I/O function

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
                ADDI  sp, sp, -16               ;
                SW    t1, 12[sp]                ;
                SW    t0, 8[sp]                 ; Push working registers onto machine stack
                SW    s0, 4[sp]                 ; 
                SW    ra, [sp]                  ;
                CSRR  t0, MCAUSE                ; Find trap cause (e.g. ECALL = 8)
                BGEZ  t0, exceptions            ; Branch if trap is an exception, otherwise an interrupt
                ANDI  t0, t0, 0x000F            ; Clear upper bits

        interrupts:     ADDI  sp, sp, -36               ;
                        SW    t2, 32[sp]                ;
                        SW    t3, 28[sp]                ;
                        SW    t4, 24[sp]                ;
                        SW    t5, 20[sp]                ; Save ENTIRE state on interrupt
                        SW    t6, 16[sp]                ; (Pushing all other used registers)
                        SW    a0, 12[sp]                ;
                        SW    a1, 8[sp]                 ;
                        SW    a2, 4[sp]                 ;
                        SW    a7, [sp]                  ;
        
                        SLLI  t0, t0, 2                 ; Multiply MCAUSE by 4 to index words
                        LA    t1, interrupt_table       ; Point to interrupt jump table
                        ADD   t1, t1, t0                ; Calculate interrupt table entry address
                        LW    t1, [t1]                  ; Load target address
                        LA    ra, interrupt_exit        ; Store return address
                        JR    t1                        ; Jump

        exceptions:     SLLI  t0, t0, 2                 ; Multiply MCAUSE by 4 to index words
                        LA    t1, exception_table       ; Point to exception jump table
                        ADD   t1, t1, t0                ; Calculate exception table entry address
                        LW    t1, [t1]                  ; Load target address
                        LA    ra, exception_exit        ; Store return address
                        JR    t1                        ; Jump

                exception_exit: CSRRW t0, MEPC, t0              ;
                                ADDI  t0, t0, 4                 ; Move MEPC to next instruction for exceptions
                                CSRRW t0, MEPC, t0              ; Ignore for interrupts
                                J trap_exit                     ;
                
                interrupt_exit: LW   a7, [sp]                   ;
                                LW   a2, 4[sp]                  ;
                                LW   a1, 8[sp]                  ;
                                LW   a0, 12[sp]                 ;
                                LW   t6, 16[sp]                 ; Save ENTIRE state on interrupt
                                LW   t5, 20[sp]                 ; (Popping all other used registers)
                                LW   t4, 24[sp]                 ;
                                LW   t3, 28[sp]                 ;
                                LW   t2, 32[sp]                 ;
                                ADDI sp, sp, 36                 ;
                
                trap_exit:      LW   ra, [sp]                   ;
                                LW   s0, 4[sp]                  ; 
                                LW   t0, 8[sp]                  ; Pop working registers from machine stack
                                LW   t1, 12[sp]                 ;
                                ADDI sp, sp, 16                 ;
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
writeLCD:       ADDI  sp, sp, -12
                SW    t0, 8[sp]
                SW    t1, 4[sp]
                SW    ra, [sp]                

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
                LI   a1, 5                      ; Delay to stretch pulse width (min 20 cycles)
                JAL delay
                
                LI   t0, 0x0000_0400            ; Load data bus bit
                SW   t0, LCD_CLEAR[s0]          ; Disable data bus (E = 0)

                LW   ra, [sp]
                LW   t1, 4[sp]
                LW   t0, 8[sp]
                ADDI sp, sp, 12
                RET


;-----------------------------------------------------
;       Function: ECALL 1
;                 Starts 1 second timer for keypad scanning
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
;                 Get character input from timer ISR queue
;          param: _
;         return: a0 = Dequeued keypad input ASCII (-1 for empty queue)
;-----------------------------------------------------
getCharacter:   ADDI sp, sp, -12
                SW   t0, 8[sp]
                SW   t1, 4[sp]
                SW   ra, [sp]

                LA   t0, keypad_queue           ; Keypad input queue base address
                LBU  t1, KP_QUEUE_SIZE[t0]      ; Current size of queue i.e. number of characters
                LI   a0, -1                     ; Dequeue error value
                BEQZ t1, queueEmpty             ; Catch queueEmpty

                ADDI t1, t1, -1
                SB   t1, KP_QUEUE_SIZE[t0]      ; Decrement queue size

                LBU  t1, KP_QUEUE_HEAD[t0]      ; Head index in queue
                ADD  t0, t0, t1                 ; Head address
                LBU  a0, [t0]                   ; Dequeue keypad input ASCII

        queueEmpty:     LW   ra, [sp]
                        LW   t1, 4[sp]
                        LW   t0, 8[sp]
                        ADDI sp, sp, 12
                        RET


;-----------------------------------------------------
;       Function: ECALL 3
;                 Checks for button press
;          param: a0 = Button Number (0x01 -> SW1, 0x02 -> SW2, 0x04 -> SW3, 0x08 -> SW4)
;         return: a0 = 0 if button pressed, unchanged if not
;-----------------------------------------------------
buttonCheck:    LI   t0, LED_BASE               ; Load LED port
                LBU  t0, BUTTONS[t0]            ; Read button inputs
                BNE  t0, a0, buttonExit         ; Check button press

                LI   a0, 0                      ; a0 = 0 for successful button press

        buttonExit:     RET


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
;
;         Timer ISR Helper functions & Data
;       
;-----------------------------------------------------
keypad_lookup:  DEFB    '#', '9', '6', '3'
                DEFB    '0', '8', '5', '2'
                DEFB    '*', '7', '4', '1' 

keypad_state:   DEFB    0, 0, 0, 0
                DEFB    0, 0, 0, 0
                DEFB    0, 0, 0, 0

keypad_queue:           DEFS    16              ; 16 Byte Queue
                        DEFB    0               ; KP_QUEUE_SIZE
                        DEFB    16              ; KP_QUEUE_CAPACITY
                        DEFB    0               ; KP_QUEUE_HEAD
                        ALIGN

queuePush:      LA   t0, keypad_queue           ; Keypad input queue base address
                LBU  t1, KP_QUEUE_CAPACITY[t0]  ; Max capacity of queue (16 bytes)
                LBU  t2, KP_QUEUE_SIZE[t0]      ; Current size of queue i.e. number of characters
                BEQ  t1, t2, queueFull          ; Catch queueFull

                LBU  t1, KP_QUEUE_HEAD[t0]      ; Head of queue
                ADD  t1, t1, t2                 ; Tail index = (head + size)
                LBU  t2, KP_QUEUE_CAPACITY[t0]  ;               % capacity
                REMU t1, t1, t2                 ;

                LBU  t2, KP_QUEUE_SIZE[t0]      ;
                ADDI t2, t2, 1                  ; Increment queue size 
                SB   t2, KP_QUEUE_SIZE[t0]      ;

                ADD  t1, t1, t0                 ; Tail address
                SB   a0, [t1]                   ; Enqueue keypad input ASCII

                RET

queueFull:      J queueFull


;-----------------------------------------------------
;       Function: Timer ISR
;                 Scan and debounce keypad, storing inputs in queue
;          param: _
;         return: _
;-----------------------------------------------------
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
                                CALL queuePush                  ;       and push to queue

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
                                CALL queuePush                  ;       and push to queue

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
                                CALL queuePush                  ;       and push to queue

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
                                CALL queuePush                  ;       and push to queue

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

;-----------------------------------------------------
;       Function: Prints string to LCD
;          param: a0 = Pointer to string
;         return: _
;-----------------------------------------------------
printString:
        ADDI sp, sp, -4
        SW   ra, [sp]                 

        MV   s0, a0                     ; Move pointer to local register
        J    printStr1

        printStrLoop:
                LI   a7, 0
                ECALL                           ; ECALL 0 prints character to LCD             
                ADDI s0, s0, 1                  ; Increment string pointer

        printStr1:
                LB   a0, [s0]                   ; Load next character
                BNEZ a0, printStrLoop           ; Write char if string pointer not at \0

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET

;-----------------------------------------------------;
;                                                     ;
;                       ROULETTE                      ;
;                                                     ;
;-----------------------------------------------------;
main:           LI   a0, 0x01                   ; Clear screen control byte
                LI   a7, 0                      ; ECALL 0 clears screen
                ECALL

        start:          LA   a0, start_string           ; Pointer to start message
                        CALL printString                ; Print start message to LCD

                startButton:    LI   a0, 1                      ; Button SW1
                                LI   a7, 3
                                ECALL                           ; ECALL 3 checks for start button press
                                BNEZ a0, startButton            ; Poll until button pressed

                        LI   a7, 1
                        ECALL                           ; ECALL 1 starts timer for keypad scanning

        placeBet:       LI   a0, 0x01                   ; Clear screen control byte
                        LI   a7, 0                      ; ECALL 0 clears screen
                        ECALL   

                                LI   s0, 0                      ; Initialising bet amount
                                LI   t0, 10                     ; Multiply current bet by 10 to add each new digit
                                LI   t1, 0x23                   ; ASCII for '#'
                                LI   t2, 0x2A                   ; ASCII for '*'
                                LI   t3, -1                     ; Get character null return

                getBet:         LI   a7, 2
                                ECALL                           ; ECALL 2 gets character from keypad input
                                BEQ  a0, t1, chooseColour       ; '#' finalises bet
                                BEQ  a0, t2, backspace          ; '*' backspace on bet amount
                                BEQ  a0, t3, getBet             ; Repeat for no character return

                                MUL  s0, s0, t0                 ; Multiply current bet by 10
                                SUBI a0, a0, 0x30               ; Subtract '0' to convert ASCII to number
                                ADD  s0, s0, a0                 ; Add new digit
                                LI   a7, 0
                                ECALL                           ; Print new digit to LCD

                                J getBet                        ; Continue keypad input until '#'

                        backspace:      ; getCursor ECALL (check not at 0 / end of 'Enter bet: ')
                        
                                        LI   a0, 0x08                   ; Backspace (BS) control byte
                                        LI   a7, 0                      ; ECALL 0 backspaces on LCD
                                        ECALL

                                        DIV  s0, s0, t0                 ; Integer division by 10 to remove last digit
                                        J getBet


                invalidBet:     LI   a0, invalid_string         ; Pointer to invalid bet string 
                                CALL printString                ; Print to LCD
                                
                                ; software delay to show message for a bit?
                                
                                J placeBet


        chooseColour:   LW   t0, balance                ; Load user's running balance
                        BLT  t0, s0, invalidBet         ; Reinput bet for insufficient balance
                        SUB  s1, t0, s0                 ; Bet value removed from balance

                        LA   a0, choose_string          ; Pointer to choose colour string
                        CALL printString                ; Print to LCD

                getColour:      LI   a7, 2                            
                                ECALL                           ; ECALL 2 gets character from keypad input
                                BEQ  a0, t3, getColour          ; Continue keypad input for no character return
                                BGT  a0, t2, getColour          ; Continue keypad input for numeric input
                                LI   s2, 0                      ; 0 for black '#'
                                BEQ  a0, t1, rouletteSpin       
                                LI   s2, 1                      ; 1 for red '*'

        rouletteSpin:   ; start timer2
                        ; timer isr: print roulette start (space | head -> tail | space)
                        ;            increment head and tail
                        ; generate random num?

        updateBalance:  ; check win status
                        ; add/subtract bet amount to balance
                        ; if balance = 0: game over
                        ; else poll for button press to next round (placeBet)

        endGame:        ; game over screen
                        ; button press to reset

stop:   J    stop


; ====================================== Input Data ==================================== 

balance         DEFW    100

start_string    DEFB    "SW1 to start\0"
ALIGN

invalid_string  DEFB    "Low balance\0"
ALIGN

choose_string   DEFB    "* = red  # = blk\0"
ALIGN

roulette        DEFB    "00|32|15|19|04|21|02|25|17|34|06|27|13|36|11|30|08|23|10|05|24|16|33|01|20|14|31|09|22|18|29|07|28|12|35|03|26|"
ALIGN

tune1	        DEFB	 8, 7
                DEFB	 0, 1
                DEFB	 8, 8
                DEFB	 9, 8
                DEFB	 7, 12
                DEFB	 8, 4
                DEFB	 9, 8

                DEFB	10, 7
                DEFB	 0, 1
                DEFB	10, 8
                DEFB	11, 8
                DEFB	10, 12
                DEFB	 9, 4
                DEFB	 8, 8

                DEFB	 9, 8
                DEFB	 8, 8
                DEFB	 7, 8
                DEFB	 8, 16

                DEFB	 0xFF
                ALIGN

; =================================== User Stack Space ================================= 

DEFS 0x1024
user_stack: