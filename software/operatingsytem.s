; ================================== Initialisation ===================================

        INCLUDE header.s
        ORG 0
        J initialisation

; ================================== Machine Tables ===================================
tables:
        exception_table         DEFW    default_exception     
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception
                                DEFW    ecallHandler    
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception       
                                DEFW    default_exception    
                                DEFW    default_exception    
                                DEFW    default_exception         

        interrupt_table         DEFW    default_interrupt    
                                DEFW    default_interrupt    
                                DEFW    default_interrupt    
                                DEFW    default_interrupt    
                                DEFW    default_interrupt    
                                DEFW    default_interrupt    
                                DEFW    default_interrupt
                                DEFW    default_interrupt    
                                DEFW    default_interrupt    
                                DEFW    default_interrupt  
                                DEFW    default_interrupt  
                                DEFW    mExtIntHandler    

        ecall_table             DEFW    writeLCD
                                DEFW    getCharacter
                                DEFW    getEvent
                                DEFW    timerStart1
                                DEFW    timerEnd1
                                DEFW    timerStart2
                                DEFW    timerEnd2
                                DEFW    buttonCheck
                                DEFW    getSystemTimer

        mExtInt_table           DEFW    timer2ISR
                                DEFW    default_mExtInt
                                DEFW    default_mExtInt
                                DEFW    default_mExtInt
                                DEFW    timer1ISR
                                DEFW    default_mExtInt
                                DEFW    default_mExtInt
                                DEFW    default_mExtInt
                                DEFW    default_mExtInt
                                DEFW    default_mExtInt
                                DEFW    default_mExtInt


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
                CSRW MEPC, ra                   ; Set previous PC to application entry

                LI   t0, PIO_BASE               ; Load PIO base address
                LI   t1, 0xFFFF_F8FF            ; Row bits (8-10) low, rest high
                SW   t1, PIO_DIR[t0]            ; Set row bits direction to output for keypad rows

                LI   t0, INTERRUPT_BASE         ; Load interrupt controller base address
                LI   t1, TIMER_INTERRUPTS       ; Both Timer interrupt (bits 0 & 4)
                SW   t1, INTERRUPT_ENABLES[t0]  ; Enable timer interrupts
                LI   t1, 0                      ; Timer to level sensitive mode
                SW   t1, INTERRUPT_MODE[t0]     ; Set modes in interrupt controller

                LI   t0, SYSTEM_BASE            ; Load system controller base address
                LI   t1, 0xC0                   ; Buzzer Bits (bits 6-7)
                SW   t1, SYSTEM_PINS[t0]        ; Redirect PIO pins to buzzer I/O function

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
                ADDI  sp, sp, -28               ;
                SW    t1, 24[sp]                ;
                SW    t0, 20[sp]                ; 
                SW    s3, 16[sp]                ;
                SW    s2, 12[sp]                ; Push working registers onto machine stack
                SW    s1, 8[sp]                 ;
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
                                LW   s1, 8[sp]                  ;
                                LW   s2, 12[sp]                 ; Pop working registers from machine stack
                                LW   s3, 16[sp]                 ;
                                LW   t0, 20[sp]                 ; 
                                LW   t1, 24[sp]                 ;
                                ADDI sp, sp, 28                 ;
                                CSRRW sp, MSCRATCH, sp          ; Save machine sp, get user sp
                                MRET


;-----------------------------------------------------
;       Function: Default Exception
;          param: _
;         return: _
;-----------------------------------------------------
default_exception:      J default_exception
                        RET


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
        
        invalid_ecall:  LI   a0, -1                     ; Set error return value

        ecall_exit:     LW   ra, [sp]
                        ADDI sp, sp, 4
                        RET


;-----------------------------------------------------
;       Function: Delay
;          param: a2 = Delay count
;         return: _
;-----------------------------------------------------
delay:  ADDI a2, a2, -1
        BNEZ a2, delay
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
                        LI   a2, 5                      ; Delay to stretch pulse width (min 20 cycles)
                        JAL  delay
                        
                        LBU  t1, LCD_DATA[s0]           ; Read LCD data 
                        ANDI t1, t1, 0b10000000         ; Isolate LCD status byte

                        LI   t0, 0x0000_0400            ; Load data bus bit
                        SW   t0, LCD_CLEAR[s0]          ; Disable data bus (E = 0)
                        LI   a2, 12                     ; Delay to separate enable pulses (min 48 cycles)
                        JAL  delay

                        BNEZ t1, idle                   ; Idle while status byte is low (display controller is busy)                   

                LI   t0, 0x0000_0100            ; Load bit for R/W
                SW   t0, LCD_CLEAR[s0]          ; Clear R/W bit to set data bus direction to write to LCD 
                
                LI   t0, LCD_CONTROL_LIMIT      ; Barrier between control & data characters
                BLT  a0, t0, skipUpdateRS       ; Characters < 0x20 keep RS = 0 to write control byte
                LI   t0, LCD_CURSOR_LIMIT       ; Barrier between data characters & LCD cursor position
                BGE  a0, t0, skipUpdateRS       ; Characters >= 0x80 keep RS = 0 to move cursor position
                LI   t0, 0x0000_0200            ; Load bit for RS
                SW   t0, LCD_SET[s0]            ; Characters >= 0x20 set RS = 1 to write data byte

        skipUpdateRS:   SB   a0, LCD_DATA[s0]           ; Output parameter byte onto data bus
                        LI   t0, 0x0000_0400            ; Load data bus bit
                        SW   t0, LCD_SET[s0]            ; Enable data bus (E = 1)
                        LI   a2, 5                      ; Delay to stretch pulse width (min 20 cycles)
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
;                 Get character input from timer1 ISR queue
;          param: _
;         return: a0 = Dequeued keypad input ASCII (-1 for empty queue)
;-----------------------------------------------------
getCharacter:   ADDI sp, sp, -12
                SW   t0, 8[sp]
                SW   t1, 4[sp]
                SW   ra, [sp]

                LA   t0, keypad_queue           ; Keypad input queue base address
                LBU  t1, QUEUE_SIZE[t0]         ; Current size of queue i.e. number of characters
                LI   a0, -1                     ; Dequeue error value
                BEQZ t1, chrQueueEmpty          ; Catch chrQueueEmpty

                ADDI t1, t1, -1
                SB   t1, QUEUE_SIZE[t0]         ; Decrement queue size

                LBU  t1, QUEUE_HEAD[t0]         ; Head index in queue
                ADD  t0, t0, t1                 ; Head address
                LBU  a0, [t0]                   ; Dequeue keypad input ASCII

        chrQueueEmpty:  LW   ra, [sp]
                        LW   t1, 4[sp]
                        LW   t0, 8[sp]
                        ADDI sp, sp, 12
                        RET


;-----------------------------------------------------
;       Function: ECALL 2
;                 Get event from timer2 ISR queue
;          param: _
;         return: a0 = State Identifier (-1 for empty queue)
;-----------------------------------------------------
getEvent:       ADDI sp, sp, -12
                SW   t0, 8[sp]
                SW   t1, 4[sp]
                SW   ra, [sp]

                LA   t0, event_queue            ; State queue base address
                LBU  t1, QUEUE_SIZE[t0]         ; Current size of queue i.e. number of characters
                LI   a0, -1                     ; Dequeue error value
                BEQZ t1, evtQueueEmpty          ; Catch evtQueueEmpty

                ADDI t1, t1, -1
                SB   t1, QUEUE_SIZE[t0]         ; Decrement queue size

                LBU  t1, QUEUE_HEAD[t0]         ; Head index in queue
                ADD  t0, t0, t1                 ; Head address
                LBU  a0, [t0]                   ; Dequeue event code

        evtQueueEmpty:  LW   ra, [sp]
                        LW   t1, 4[sp]
                        LW   t0, 8[sp]
                        ADDI sp, sp, 12
                        RET


;-----------------------------------------------------
;       Function: ECALL 3
;                 Starts 1 millisecond timer for keypad scanning
;          param: _
;         return: _
;-----------------------------------------------------
timerStart1:    LI   s0, TIMER1_BASE
                LI   t0, 999
                SW   t0, TIMER_LIMIT[s0]        ; Set limit to 1ms
                LI   t0, 0b1011
                SW   t0, TIMER_SET[s0]          ; Turn on counter enable, modulus and interrupt control bits
                RET


;-----------------------------------------------------
;       Function: ECALL 4
;                 Ends 1 millisecond timer for keypad scanning
;          param: _
;         return: _
;-----------------------------------------------------
timerEnd1:      LI   s0, TIMER1_BASE
                LI   t0, 1
                SW   t0, TIMER_CLEAR[s0]        ; Clear timer enable bit
                RET


;-----------------------------------------------------
;       Function: ECALL 5
;                 Starts 0.5s timer for roulette spin
;          param: _
;         return: _
;-----------------------------------------------------
timerStart2:    LI   s0, TIMER2_BASE
                LI   t0, 199999
                SW   t0, TIMER_LIMIT[s0]        ; Set limit to 0.5s
                LI   t0, 0b1011
                SW   t0, TIMER_SET[s0]          ; Turn on counter enable, modulus and interrupt control bits
                RET


;-----------------------------------------------------
;       Function: ECALL 6
;                 Ends 0.5 second timer for keypad scanning
;          param: _
;         return: _
;-----------------------------------------------------
timerEnd2:      LI   s0, TIMER2_BASE
                LI   t0, 1
                SW   t0, TIMER_CLEAR[s0]        ; Clear timer enable bit
                RET


;-----------------------------------------------------
;       Function: ECALL 7
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
;       Function: ECALL 8
;                 Gets current processor timer
;          param: _
;         return: a0 = Low 32 bits of RISC-V clock
;-----------------------------------------------------
getSystemTimer: LI   t0, SYSTEM_BASE
                LW   a0, SYSTEM_TIME_LOW[t0]
                RET


;-----------------------------------------------------
;       Function: Default Interrupt
;          param: _
;         return: _
;-----------------------------------------------------
default_interrupt:      J default_interrupt
                        RET


;-----------------------------------------------------
;       Function: Default Machine External Interrupt
;          param: _
;         return: _
;-----------------------------------------------------
default_mExtInt:        J default_mExtInt
                        RET


;-----------------------------------------------------
;       Function: Machine External Interrupt Handler
;          param: _
;         return: _
;-----------------------------------------------------
mExtIntHandler: ADDI sp, sp, -4
                SW   ra, [sp]

                LI   s0, INTERRUPT_BASE
                LW   t0, INTERRUPT_REQUESTS[s0]         ; Read requests (input state of enabled interrupts)
                        LI   t1, -4                     ; Initialise counter to find interrupt request
        request_loop:   SRLI t0, t0, 1                  ; Shift request bits right until interrupt found
                        ADDI t1, t1, 4                  ; Increment interrupt request counter in words
                        BNEZ t0, request_loop           ; Loop until interrupt request found

                LA   t0, mExtInt_table          ; Point to Machine External Interrupt jump table
                ADD  t0, t0, t1                 ; Calculate table entry address
                LW   t0, [t0]                   ; Load target address
                JALR t0                         ; Jump

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET
                
;-----------------------------------------------------
;
;         Timer ISR Data & Helper functions
;       
;-----------------------------------------------------
keypad_lookup:  DEFB    '#', '9', '6', '3'
                DEFB    '0', '8', '5', '2'
                DEFB    '*', '7', '4', '1' 

keypad_state:   DEFB    0, 0, 0, 0
                DEFB    0, 0, 0, 0
                DEFB    0, 0, 0, 0

                        STRUCT
QUEUE                   DOUBLEWORD
QUEUE_SIZE              BYTE
QUEUE_CAPACITY          BYTE
QUEUE_HEAD              BYTE

keypad_queue:           DEFS    8               ; 8 Byte Queue
                        DEFB    0               ; KP_QUEUE_SIZE
                        DEFB    8               ; KP_QUEUE_CAPACITY
                        DEFB    0               ; KP_QUEUE_HEAD
                        ALIGN

event_queue:            DEFS    8               ; 8 Byte Queue
                        DEFB    0               ; EVENT_QUEUE_SIZE
                        DEFB    8               ; EVENT_QUEUE_CAPACITY
                        DEFB    0               ; EVENT_QUEUE_HEAD
                        ALIGN


;-----------------------------------------------------
;       Function: Pushes to 16 byte queue
;          param: a0 = Byte to push, a1 = Queue base address
;         return: _
;-----------------------------------------------------
queuePush:      LBU  t0, QUEUE_CAPACITY[a1]     ; Max capacity of queue (16 bytes)
                LBU  t1, QUEUE_SIZE[a1]         ; Current size of queue i.e. number of characters
                BEQ  t0, t1, pushExit           ; Catch full queue

                LBU  t0, QUEUE_HEAD[a1]         ; Head of queue
                ADD  t0, t0, t1                 ; Tail index = (head + size)
                LBU  t1, QUEUE_CAPACITY[a1]     ;               % capacity
                REMU t0, t0, t1                 ;

                LBU  t1, QUEUE_SIZE[a1]         ;
                ADDI t1, t1, 1                  ; Increment queue size 
                SB   t1, QUEUE_SIZE[a1]         ;

                ADD  a1, a1, t0                 ; Tail address
                SB   a0, [a1]                   ; Enqueue keypad input ASCII

        pushExit:       RET


;-----------------------------------------------------
;       Function: Timer1 ISR
;                 Scan and debounce keypad, storing inputs in queue
;          param: _
;         return: _
;-----------------------------------------------------
timer1ISR:      ADDI sp, sp, -4
                SW   ra, [sp]

                LI   s0, PIO_BASE               ; Keypad connected through PIO
                LI   s1, 2                      ; Loop counter (int i = 2; i >= 0; i--)
                LI   s2, 0x0000_0100            ; Bit 8 (first row of keypad)
                LA   a1, keypad_queue           ; Character queue base address

        rowLoop:        SW   s2, PIO_SET[s0]            ; Activate current row
                        NOP
                        NOP
                        LW   t2, PIO_DATA[s0]           ; Read keypad state at current row 
                        LI   t3, 0x0000_F000            ; Column bits (12-15) mask
                        AND  t2, t2, t3                 ; Isolate column bits
                        SRLI t2, t2, 12                 ; Shift column bits down to bits 0-3

                        LA   t3, keypad_lookup          ; Pointer to keypad ASCII lookup table
                        LA   t4, keypad_state           ; Pointer to keypad rolling state
                        SLLI t5, s1, 2                  ; Multiply loop counter by 4 to index table row
                        ADD  t3, t3, t5                 ; Apply row offset to keypad_lookup base
                        ADD  t4, t4, t5                 ; Apply row offset to keypad_state base
                        LI   s3, 3                      ; Loop counter (int j = 3, j >= 0, j--)

                colLoop:        LBU  t5, [t4]                   ; Read current key state
                                XORI t6, t5, 0x7F               ; Toggle all but most significant bit
                                BNEZ t6, nextCol                ; Continue if key state is not ready (given next input)                
                                ANDI t6, t2, 1                  ; Check if current key (row, col) is pressed
                                LI   a0, 1                      ; Compare against current key press status
                                BNE  t6, a0, nextCol            ; Continue if last 1 needed for FF key state is not set
                                LBU  a0, [t3]                   ; Else, load relevant character
                                CALL queuePush                  ;       and push to queue

                    nextCol:    SLLI t5, t5, 1                  ; Shift rolling key state to make room to update 
                                ANDI t6, t2, 1
                                ADD  t5, t5, t6                 ; Update rolling key state with 0/1 in LSB
                                SB   t5, [t4]                   ; Write back key state
                                SRLI t2, t2, 1                  ; Shift to read next column
                                ADDI t3, t3, 1                  ; Increment keypad ASCII lookup table pointer
                                ADDI t4, t4, 1                  ; Increment keypad rolling state pointer
                                ADDI s3, s3, -1                 ; Decrememnt column loop counter
                                BGEZ s3, colLoop

                        SW   s2, PIO_CLEAR[s0]          ; Inactivate current row
                        SLLI s2, s2, 1                  ; Move to scan next row
                        ADDI s1, s1, -1                 ; Decrement loop counter
                        LI   a2, 10
                        CALL delay
                        BGEZ s1, rowLoop                ; Loop to scan next row

                LI   s0, TIMER1_BASE
                LI   t0, 0x80000000
                SW   t0, TIMER_CLEAR[s0]        ; Clear timer sticky bit

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET

;-----------------------------------------------------
;       Function: Timer2 ISR
;                 Pushes SPIN_EVENT to event queue
;          param: _
;         return: _
;-----------------------------------------------------
timer2ISR:      ADDI sp, sp, -4
                SW   ra, [sp]

                LI   a0, SPIN_EVENT  
                LA   a1, event_queue            
                CALL queuePush                  ; Push a spin event to event queue

                LI   s0, TIMER2_BASE
                LI   t0, 0x80000000
                SW   t0, TIMER_CLEAR[s0]        ; Clear timer sticky bit

                LW   ra, [sp]
                ADDI sp, sp, 4
                RET


; ================================= Machine Stack Space ================================

DEFS 0x1024
machine_stack:
