// TLB holding stage 2 only entries (IPA page to PA page) and combined entries
// (VA page to PA page), tagged with VMID and, for combined entries, ASID.
// Broadcast TLBI scopes follow spec/sail/tlbi_scope.sail:
//   IPAS2E1IS    stage 2 entries of that VMID and IPA page
//   VMALLE1IS    combined entries of that VMID
//   VMALLS12E1IS every entry of that VMID
//   VAE1IS       combined entries of that VMID and VA page, ASID or global
module s2_tlb #(parameter int N = 8) (
  input  logic        clk,
  input  logic        rst_n,
  // lookup, combinational
  input  logic        lk_combined,
  input  logic [15:0] lk_vmid,
  input  logic [15:0] lk_asid,
  input  logic [35:0] lk_page,
  output logic        lk_hit,
  output logic [35:0] lk_pa,
  // fill
  input  logic        fill,
  input  logic        fill_combined,
  input  logic [15:0] fill_vmid,
  input  logic [15:0] fill_asid,
  input  logic        fill_global,
  input  logic [35:0] fill_page,
  input  logic [35:0] fill_pa,
  // broadcast invalidate
  input  logic        tlbi,
  input  logic [1:0]  tlbi_op,     // 0 IPAS2E1IS, 1 VMALLE1IS, 2 VMALLS12E1IS, 3 VAE1IS
  input  logic [15:0] tlbi_vmid,
  input  logic [15:0] tlbi_asid,
  input  logic [35:0] tlbi_page
);
  localparam int IW = (N > 1) ? $clog2(N) : 1;
  logic [N-1:0] v, cb, gl;
  logic [15:0]  vmid [N];
  logic [15:0]  asid [N];
  logic [35:0]  page [N];
  logic [35:0]  pa   [N];
  logic [IW-1:0] rr;

  always_comb begin
    lk_hit = 1'b0; lk_pa = '0;
    for (int i = 0; i < N; i++)
      if (v[i] && cb[i] == lk_combined && vmid[i] == lk_vmid && page[i] == lk_page &&
          (!lk_combined || gl[i] || asid[i] == lk_asid)) begin
        lk_hit = 1'b1; lk_pa = pa[i];
      end
  end

  logic [N-1:0] kill;
  always_comb begin
    for (int i = 0; i < N; i++) begin
      kill[i] = 1'b0;
      if (tlbi && v[i] && vmid[i] == tlbi_vmid)
        unique case (tlbi_op)
          2'd0: kill[i] = !cb[i] && page[i] == tlbi_page;
          2'd1: kill[i] = cb[i];
          2'd2: kill[i] = 1'b1;
          default: kill[i] = cb[i] && page[i] == tlbi_page && (gl[i] || asid[i] == tlbi_asid);
        endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      v <= '0; cb <= '0; gl <= '0; rr <= '0;
      for (int i = 0; i < N; i++) begin vmid[i] <= '0; asid[i] <= '0; page[i] <= '0; pa[i] <= '0; end
    end else begin
      v <= v & ~kill;
      if (fill) begin
        v[rr] <= 1'b1; cb[rr] <= fill_combined; gl[rr] <= fill_global;
        vmid[rr] <= fill_vmid; asid[rr] <= fill_asid; page[rr] <= fill_page; pa[rr] <= fill_pa;
        rr <= (rr == IW'(N - 1)) ? '0 : rr + 1'b1;
      end
    end
  end
endmodule
