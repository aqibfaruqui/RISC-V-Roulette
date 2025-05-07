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
  
reg  [15:0] addr;  /* Note : if read needed the appropriate address bits must */
                   /* be kept for the output multiplexer in the -next- cycle. */

reg  [15:0] freq;                                        /* Frequency divisor */
reg  [15:0] duration;                                        /* Note duration */
reg  [15:0] counter;                                 /* Clock divider counter */
reg  [31:0] buzzer;                                       /* Output to buzzer */
reg         state;                                /* Oscilatting buzzer state */

assign stall_o =    cs_i   && 1'b0;       /* Unlikely to want to change these */
assign abort_o = {3{cs_i}} && 3'h0;     /* Aborts done at 'MMU' level already */
assign LED_o   = 8'h00;                        /* Wire off the LED outputs    */
assign irq_o          =  4'b0000;  /* Potential interrupt requests (tied off) */

always @ (posedge clk)                         /* Address bits hold           */
if (cs_i && read_i) addr <= address_i[7:0];    /* Delay for next cycle        */

always @ (posedge clk)                         /* Write register: not decoded */

// Initialisation value(s)
if (reset)
  begin
    freq <= 16'h0000_0000;                       
    duration <= 16'h0000_0000;                    
    counter <= 16'h0000_0000;
    buzzer <= 32'h0000_0000;
    state <= 1'h0;
  end

// Register updates
else
  begin
    if (cs_i && write_i)                         /* Write to selected register  */
      case (address_i[3:2])                      /* Select (word) address here  */
        2'h0: begin
          freq <= data_in[15:0];       /* Frequency divisor written from software */
          duration <= data_in[31:16];     /* Note duration written from same word */
        end    
      endcase

    // Clock divider logic
    if (freq != 0)
      begin
      if (counter == 0)
        begin
          counter <= freq;                                    /* Reload counter */
          state <= ~state;                               /* Toggle buzzer state */
        end
      else
        begin
          counter <= counter - 1;
        end
      end
    else
      begin
        state <= 1'h0;                               /* Buzzer off if freq == 0 */
      end
  end

always @ (*)                                   /* Read from selected register */
  begin
    case (addr[3:2])                /* Select (word) address here (later cycle) */
      2'h0: data_out = 32'h1010_1010;
      default: data_out = 32'hxxxx_xxxx; /* Guard against accidentally latching */
    endcase
    if (freq != 0)
      buzzer     = state ? 32'h0000_0040 : 32'h0000_0080;              /* Buzzer on */
    else
      buzzer     = 32'h0;                                             /* Buzzer off */
  end

// port_in                             /* Up to 32 potential inputs (unwired) */
assign port_direction = 32'hFFFF_FF3F;                  /* Enables (bits 6 and 7 output) */
assign port_out = buzzer;
   
endmodule  // user_periph

/*============================================================================*/