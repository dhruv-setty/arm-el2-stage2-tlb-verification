// Stage 2 translation table walker: 4 KiB granule, 48 bit IPA, start level 0
// (VTCR_EL2.T0SZ 16), after ARM DDI 0487K. Same rules and result encoding as
// spec/sail/stage2.sail, which is the reference it is tested against.
//
// resp[63] fault, resp[62:60] kind (1 translation, 2 access flag,
// 3 permission), resp[59:58] level, resp[47:0] output address.
module s2_walker (
  input  logic        clk,
  input  logic        rst_n,
  // request
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [47:0] vttbr,
  input  logic [47:0] ipa,
  input  logic        write,
  // response, one cycle pulse
  output logic        resp_valid,
  output logic [63:0] resp,
  // table memory, one read in flight
  output logic        mem_req,
  output logic [47:0] mem_addr,
  input  logic        mem_rvalid,
  input  logic [63:0] mem_rdata
);
  typedef enum logic [1:0] { IDLE, READ, WAIT } state_t;
  state_t state;

  logic [47:0] table_q, ipa_q;
  logic        write_q;
  logic [1:0]  level;

  logic [8:0] idx;
  always_comb begin
    unique case (level)
      2'd0: idx = ipa_q[47:39];
      2'd1: idx = ipa_q[38:30];
      2'd2: idx = ipa_q[29:21];
      default: idx = ipa_q[20:12];
    endcase
  end

  assign req_ready = (state == IDLE);
  assign mem_req   = (state == READ);
  assign mem_addr  = {table_q[47:12], idx, 3'b000};

  function automatic logic [63:0] fault(input logic [2:0] kind, input logic [1:0] l);
    fault = {1'b1, kind, l, 58'd0};
  endfunction

  logic [63:0] d;
  assign d = mem_rdata;
  logic perm_ok;
  assign perm_ok = write_q ? d[7] : d[6];

  logic [47:0] oa;
  always_comb begin
    unique case (level)
      2'd1: oa = {d[47:30], ipa_q[29:0]};
      2'd2: oa = {d[47:21], ipa_q[20:0]};
      default: oa = {d[47:12], ipa_q[11:0]};
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE; resp_valid <= 1'b0; resp <= '0;
      table_q <= '0; ipa_q <= '0; write_q <= 1'b0; level <= 2'd0;
    end else begin
      resp_valid <= 1'b0;
      unique case (state)
        IDLE: if (req_valid) begin
          table_q <= {vttbr[47:12], 12'd0};
          ipa_q   <= ipa;
          write_q <= write;
          level   <= 2'd0;
          state   <= READ;
        end
        READ: state <= WAIT;
        WAIT: if (mem_rvalid) begin
          if (!d[0]) begin
            resp <= fault(3'd1, level); resp_valid <= 1'b1; state <= IDLE;
          end else if (level != 2'd3 && d[1]) begin
            table_q <= {d[47:12], 12'd0}; level <= level + 2'd1; state <= READ;
          end else if (level == 2'd0 || (level == 2'd3 && !d[1])) begin
            resp <= fault(3'd1, level); resp_valid <= 1'b1; state <= IDLE;
          end else if (!d[10]) begin
            resp <= fault(3'd2, level); resp_valid <= 1'b1; state <= IDLE;
          end else if (!perm_ok) begin
            resp <= fault(3'd3, level); resp_valid <= 1'b1; state <= IDLE;
          end else begin
            resp <= {16'd0, oa}; resp_valid <= 1'b1; state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
