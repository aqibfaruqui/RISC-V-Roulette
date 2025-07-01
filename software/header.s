NUM_ECALLS              EQU         9
TIMER_INTERRUPTS        EQU         0x11
SPIN_EVENT              EQU         1

LED_BASE                EQU         0x0001_0000
LED_PORT                EQU         0x0
BUTTONS                 EQU         0x1

LCD_BASE                EQU         0x0001_0100
LCD_DATA                EQU         0x0
LCD_CONTROL             EQU         0x1
LCD_CLEAR               EQU         0x8
LCD_SET                 EQU         0xC
LCD_CONTROL_LIMIT       EQU         0x20
LCD_CURSOR_LIMIT        EQU         0x80

TIMER1_BASE             EQU         0x0001_0200
TIMER_COUNTER           EQU         0x0
TIMER_LIMIT             EQU         0x4
TIMER_STATUS            EQU         0xC
TIMER_CLEAR             EQU         0x10
TIMER_SET               EQU         0x14

PIO_BASE                EQU         0x0001_0300
PIO_DATA                EQU         0x0
PIO_DIR                 EQU         0x4
PIO_CLEAR               EQU         0x8 
PIO_SET                 EQU         0xC

INTERRUPT_BASE          EQU         0x0001_0400
INTERRUPT_INPUTS        EQU         0x0
INTERRUPT_ENABLES       EQU         0x4
INTERRUPT_REQUESTS      EQU         0x8
INTERRUPT_MODE          EQU         0xC
INTERRUPT_EDGE_CLEAR    EQU         0x10
INTERRUPT_EDGE_SET      EQU         0x14
INTERRUPT_OUTPUT        EQU         0x1C

SYSTEM_BASE             EQU         0x0001_0700
SYSTEM_HALT             EQU         0x0
SYSTEM_CLOCK            EQU         0x4 
SYSTEM_PINS             EQU         0x8 
SYSTEM_LED              EQU         0xC
SYSTEM_LCD              EQU         0xD
SYSTEM_TIME_LOW         EQU         0x10
SYSTEM_TIME_HIGH        EQU         0x14 
SYSTEM_TIME_COMP_LOW    EQU         0x18
SYSTEM_TIME_COMP_HIGH   EQU         0x1C

BUZZER_BASE             EQU         0x0002_0000
BUZZER_FREQ             EQU         0x0

TIMER2_BASE             EQU         0x0002_0100
