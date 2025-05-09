/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -*/
/* General timer - used by both subsystems                                    */

module timer (input  wire        clk,
              input  wire        reset,

//            input  wire        clk_en,                     /* From prescale */

              input  wire        cs_i,
              input  wire        read_i,
              input  wire        write_i,
              input  wire [31:0] address_i,
              input  wire  [1:0] mode_i,
              input  wire  [1:0] size_i,
              output wire        stall_o,
              output wire  [2:0] abort_v_o,
              input  wire [31:0] data_in,
              output reg  [31:0] data_out,
              output wire        ireq_o);

localparam PRE_MOD = (`CLOCK_FREQUENCY / `TIMER_FREQUENCY) - 1;

reg   [9:0] prescale;                                            /* Prescaler */
wire        clk_en;

reg  [31:0] count;
reg  [31:0] limit;
reg         terminal;
reg  [29:0] control;
reg         enabled;

wire [31:0] ctrl_rd;                          /* Assembly of bits for reading */

wire        match;                                  /* Terminal count reached */
wire        modulo;                           /* Alias for use limit register */
wire        once;                             /* Alias for one-time counting  */

wire        stop;                                   /* Auto-disable condition */
wire        clear_term;

assign stall_o   =    cs_i   && 1'b0;
assign abort_v_o = {3{cs_i}} && 3'h0;

always @ (posedge clk)                                           /* Prescaler */
if (reset) prescale <= 9'h000;
else   if (prescale == 9'h000) prescale <= PRE_MOD;
       else                    prescale <= prescale - 9'h01;

assign clk_en = (prescale == 9'h000);

assign modulo = control[0];
assign once   = control[1];
assign match  = (modulo) ? (count >= limit) : (count == 32'hFFFF_FFFF);
                   /* >= so that limit changes reset counter when appropriate */

assign stop   = once && match && clk_en;                 /* Disable self next */

always @ (posedge clk)                                     /* Register writes */
begin
if (reset) count <= 32'h0000_0000;
else
  if (cs_i && write_i && (address_i[4:3] == 2'b00))                /* Counter */
    if (address_i[2] == 1'h0) count <= data_in;
    else begin
         if (count > data_in) count <= 32'h0000_0000;          /* Limit write */
         end
  else
    if (enabled && clk_en)                                      /* If enabled */
      if (match) count <= 32'h0000_0000;
      else       count <= count + 32'h0000_0001;

if (reset) limit <= 32'h0000_0000;                                   /* Limit */
else
  if (cs_i && write_i && (address_i[4:2] == 3'h1)) limit <= data_in;

if (reset)
  begin
  control <= 30'h0000_0000;                               /* Control register */
  enabled <=  1'b0;
  end
else
  begin
  if (cs_i && write_i)
    case (address_i[4:2])
      3'h3: begin
            control <= data_in[30:1];
            enabled <= data_in[0];
            end
      3'h4: begin
            control <= control & ~data_in[30:1];
            if (data_in[0] == 1'b1) enabled <= 1'b0;
            else if (stop)          enabled <= 1'b0;
            end
      3'h5: begin
            control <= control |  data_in[30:1];
            if (data_in[0] == 1'b1) enabled <= 1'b1;
            else if (stop)          enabled <= 1'b0;
            end
      default:   if (stop) enabled <= 1'b0;
      endcase
  else if (stop) enabled <= 1'b0;
                             /* Disable if terminal count in single shot mode */
  end

end

assign clear_term = ((cs_i && write_i)
                  && ((address_i[4:3] == 2'h0)    /* Writes to count or limit */
                  || ((address_i[4:2] == 3'h4)     /* Explicit clear bit (x2) */
                            && ((data_in[31] | data_in[4]) == 1'b1))
                  || ((address_i[4:2] == 3'h3)              /* Write bit to 0 */
                            && ((data_in[31] == 1'b0)))));

always @ (posedge clk)                                    /* Read sensitivity */
if (reset)                           terminal <= 1'b0;
else if (enabled && clk_en && match) terminal <= 1'b1;         /* Set, sticky */
     else if (clear_term)            terminal <= 1'b0;

assign ctrl_rd = {terminal, control, enabled};

// Latch address (etc.) & output from source? (saves big register) @@@
always @ (posedge clk)                                      /* Register reads */
if (cs_i && read_i)
  case (address_i[4:2])
    3'h0: data_out <= count;
    3'h1: data_out <= limit;
    3'h3: data_out <= ctrl_rd;
    default:
          data_out <= 32'h0000_0000;
  endcase
else      data_out <= 32'hxxxx_xxxx;

assign ireq_o = terminal && control[2];           /* Terminal count and IrqEn */

endmodule	// timer

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -*/
