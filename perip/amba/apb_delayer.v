module apb_delayer(
  input  logic        clock,
  input  logic        reset,
  input  logic [31:0] in_paddr,
  input  logic        in_psel,
  input  logic        in_penable,
  input  logic [2:0]  in_pprot,
  input  logic        in_pwrite,
  input  logic [31:0] in_pwdata,
  input  logic [3:0]  in_pstrb,
  output logic        in_pready,
  output logic [31:0] in_prdata,
  output logic        in_pslverr,

  output logic [31:0] out_paddr,
  output logic        out_psel,
  output logic        out_penable,
  output logic [2:0]  out_pprot,
  output logic        out_pwrite,
  output logic [31:0] out_pwdata,
  output logic [3:0]  out_pstrb,
  input  logic        out_pready,
  input  logic [31:0] out_prdata,
  input  logic        out_pslverr
);
/*
cf = 507.701 MHz
df = 100.000 MHz
r = cf / df = 5.07701
s = 100_000
r*s = 507_701
*/

 localparam S  = 100_000;
 localparam RS = 507_701;

  typedef enum logic [1:0] {
    IDLE, WAIT, DELAY
  } apb_state;

  apb_state next_state;
  apb_state curr_state;

  logic [31:0] in_prdata_d;
  logic        in_pslverr_d;
  logic        out_psel_q, out_psel_d;

  logic [63:0] wait_counter, wait_counter_d; // counts number of device cycles to wait for response times R*S

  assign out_paddr   = in_paddr;
  assign out_penable = in_penable;
  assign out_pprot   = in_pprot;
  assign out_pstrb   = in_pstrb;
  assign out_pwdata  = in_pwdata;
  assign out_pwrite  = in_pwrite;

  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      in_prdata    <= 32'b0;
      in_pslverr   <= 1'b0;
      wait_counter <= 64'b0;
      curr_state   <= IDLE;
    end
    else begin
      in_prdata    <= in_prdata_d;
      in_pslverr   <= in_pslverr_d;
      wait_counter <= wait_counter_d;
      curr_state   <= next_state;
    end
  end

  always_comb begin
    in_pready     = 1'b0;
    in_prdata_d   = in_prdata;
    in_pslverr_d  = in_pslverr;
    out_psel      = 1'b0;
    case (curr_state)
      IDLE: begin
        next_state   = IDLE;
        in_prdata_d  = 32'b0;
        in_pslverr_d = 1'b0;
        if (in_psel) begin
          out_psel       = 1'b1;
          next_state     = WAIT;
        end
      end
      WAIT: begin
        out_psel       = 1'b1;
        if (out_pready) begin
          in_pready    = 1'b0;
          in_prdata_d  = out_prdata;
          in_pslverr_d = out_pslverr;
          next_state   = DELAY;
        end
        else begin
          wait_counter_d = wait_counter + RS;
          next_state = WAIT;
        end
      end
      DELAY: begin
        if (wait_counter < S) begin
          // NOTE: Here wait_counter is non-zero -- which is okay -- since we want to wait this fractional <1 cycle.
          //       Therefore, we simply accumulate this fractional wait_counter delay for the next request.
          in_pready  = 1'b1;
          next_state = IDLE;
        end
        else begin
          wait_counter_d = wait_counter - S;
          next_state = DELAY;
        end
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end
  
`ifdef verilator
/* verilator lint_off UNUSEDSIGNAL */
reg [71:0]  dbg_apb;

always @ * begin
  case (curr_state)
    IDLE      : dbg_apb = "APB_IDLE";
    WAIT      : dbg_apb = "APB_WAIT";
    DELAY     : dbg_apb = "APB_DELAY";
    default   : dbg_apb = "APB_NONE";
  endcase
end
/* verilator lint_on UNUSEDSIGNAL */
`endif
endmodule
