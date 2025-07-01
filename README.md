# RISC-V Roulette

A RISC-V mini operating system and custom hardware peripherals for roulette on FPGA

## Overview

- **Software:**
  - `operatingsystem.s:` Simple OS handling system calls and interrupts, with: 
    - Linux-style syscall bounds checking 
    - Keypad scanning & debouncing
    - Circular queues for interrupt-driven keypad input and event handling   
  - `roulette.s:` Roulette application running on the operating system, with:
    - Dual hardware interrupt-driven timers for parallel keypad input and roulette spin event generation
    - Support for multi-digit bet input and rolling rounds of roulette
    - Random number generation for fair roulette spins displayed on HD44780 LCD
    - Efficient pointer arithmetic for win/loss tracking

- **Hardware:**  
  - `User_Peripherals.v:` Base peripheral infrastructure for memory-mapped I/O, implementing:
    - Interrupt-driven timer for keypad scanning and spin events
    - Square wave buzzer capable of playing various pitches