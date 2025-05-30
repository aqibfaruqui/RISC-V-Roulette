/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -*/
/* This is a dummy I/O cell which acts as a template for user hardware.       */
/* It can accommodate 16 KiW (64 KiB) of I/O registers: currently two 32-bit  */
/* registers {yyy, zzz} are implemented, aliased throughout the address space.*/
/* The template is provided with 32 I/O lines which can be routed through to  */
/* the PCB I/O connectors on a bitwise basis in software.                     */
/* Four expansion interrupt signals are also provided.                        */
/* Currently uncommitted outputs are wired to constant values.                */
/*                                                          AMM/JDG Feb. 2025 */
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -*/

module User_Peripheral (input  wire        clk,           /* System clock     */
                        input  wire        reset,         /* System reset     */
                        input  wire        cs_i,          /* Device select    */
                        input  wire        read_i,        /* Bus read select  */
                        input  wire  [1:0] size_i,        /* Transfer size    */
                        input  wire        write_i,       /* Bus write select */
                        input  wire  [1:0] mode_i,        /* Privilege mode   */
                        input  wire [31:0] address_i,     /* Processor address*/
                        output wire        stall_o,       /* Bus wait output  */
                        output wire  [2:0] abort_o,       /* Bus error        */
                        input  wire [31:0] data_in,       /* Store data bus   */
                        output reg  [31:0] data_out,      /* Load data bus    */

                        input  wire [31:0] port_in,       /*Connections towards 
                                                          /*      pin_fn      */
                        output wire [31:0] port_out, 
                        output wire [31:0] port_direction,/* 1nput or 0utput  */
                        output wire  [7:0] LED_o,         /* Connections towards
                                                          /*   PCB LEDs       */
                        input  wire  [3:0] switch_i,      /* PCB switch states*/
                        output wire  [3:0] irq_o);        /*Interrupt requests*/

`define CLK_10ms        32'd400_000             /* 10 milliseconds on 40MHz clock */     

`define BUZZER_LEFT     32'h0000_0040      /* Bits 6 & 7 for each buzzer terminal */
`define BUZZER_RIGHT    32'h0000_0080

`define P_BUZZER        8'h00                               /* I/O device offsets */
`define P_TIMER2        8'h01

reg  [15:0] addr;  /* Note : if read needed the appropriate address bits must */
                   /* be kept for the output multiplexer in the -next- cycle. */

reg  [15:0] frequency;                            /* Input: Frequency divisor */
reg  [15:0] duration;                                 /* Input: Note duration */
reg  [15:0] freq_counter;                   /* Counter to decrement frequency */
reg  [15:0] clk_counter;               /* Counter to track duration (seconds) */
reg  [31:0] buzzer;                                       /* Output to buzzer */
reg         state;                                /* Oscilatting buzzer state */
wire        cs_buzzer;                      /* Buzzer chip select @ 0002_00xx */

wire [31:0] timer2_data_out;                     /* Data out from timer module*/
wire        timer2_irq;                 /* Interrupt request from timer module*/
wire        cs_timer2;                      /* Timer2 chip select @ 0002_01xx */

assign stall_o    = cs_i   && 1'b0;          /* Unlikely to want to change these */
assign abort_o    = {3{cs_i}} && 3'h0;     /* Aborts done at 'MMU' level already */
assign LED_o      = 8'h00;                        /* Wire off the LED outputs    */
assign irq_o[3:1] = 3'b000;           /* Potential interrupt requests (tied off) */
assign irq_o[0]   = timer2_irq;

assign cs_buzzer = cs_i && (address_i[15:8] == `P_BUZZER);     /*  Buzzer in space 0002_00xx */
assign cs_timer2 = cs_i && (address_i[15:8] == `P_TIMER2);     /*  Timer2 in space 0002_01xx */

always @ (posedge clk)                          /* Address bits hold           */
if (cs_i && read_i) addr <= address_i[15:0];    /* Delay for next cycle        */

always @ (posedge clk)                          /* Write register: not decoded */
  // Initialisation value(s)
  if (reset)
    begin
      frequency     <= 16'h0;                       
      duration      <= 16'h0;                    
      freq_counter  <= 16'h0;
      clk_counter   <= 16'h0;
      buzzer        <= 32'h0;
      state         <= 1'h0;
    end

  // Register updates
  else 
  begin
    if (cs_buzzer && write_i && address_i[3:2] == 2'b00) begin
      frequency     <= data_in[31:16];              /* Frequency divisor from top half */
      duration      <= data_in[15:0] * `CLK_10ms;    /* Note duration from bottom half */
      clk_counter   <= 16'h0;
    end

    // Clock divider logic
    if (frequency != 0 && duration != 0)

      // Inverting buzzer at note frequency
      if (freq_counter != 0) freq_counter <= freq_counter - 1;
      else begin
          freq_counter <= frequency;                          /* Reload counter */
          state        <= ~state;                        /* Toggle buzzer state */
      end

      // Playing for length of note duration
      if (clk_counter >= duration) buzzer = 32'h0;
      else begin
        buzzer        <= state ? `BUZZER_LEFT : `BUZZER_RIGHT;
        clk_counter   <= clk_counter + 16'h0000_0001;
      end
  end

always @ (*)                                   /* Read from selected register */
  case (address_i[15:8])
    `P_BUZZER:   data_out = frequency;             /*  Buzzer in space 0002_00xx */
    `P_TIMER2:   data_out = timer2_data_out;       /*  Timer2 in space 0002_01xx */
    default:     data_out = 32'hxxxx_xxxx;
  endcase

// port_in                                /* Up to 32 potential inputs (unwired) */
assign port_direction = 32'hFFFF_FF3F;          /* Enables (bits 6 and 7 output) */
assign port_out = buzzer;

timer timer2    (.clk      (clk),
                .reset     (reset),
                .cs_i      (cs_timer2),
                .read_i    (read_i),
                .write_i   (write_i),
                .address_i (address_i),
                .mode_i    (mode_i),
                .size_i    (size_i),
                .stall_o   (stall_o),
                .abort_v_o (abort_o),
                .data_in   (data_in),
                .data_out  (timer2_data_out),
                .ireq_o    (timer2_irq));

endmodule  // user_periph

/*============================================================================*/