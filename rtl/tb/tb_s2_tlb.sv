// Directed test of rtl/s2_tlb.sv: the TLBI scope cases of
// spec/sail/checks.sail, plus lookup tagging by VMID and ASID.
`timescale 1ns/1ps
module tb_s2_tlb;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic lk_combined; logic [15:0] lk_vmid, lk_asid; logic [35:0] lk_page;
  logic lk_hit; logic [35:0] lk_pa;
  logic fill = 0, fill_combined, fill_global; logic [15:0] fill_vmid, fill_asid; logic [35:0] fill_page, fill_pa;
  logic tlbi = 0; logic [1:0] tlbi_op; logic [15:0] tlbi_vmid, tlbi_asid; logic [35:0] tlbi_page;
  int errors = 0;

  s2_tlb #(.N(8)) dut (.*);

  task automatic put(input bit c, input [15:0] vm, input [15:0] as, input bit g, input [35:0] pg, input [35:0] p);
    @(negedge clk); fill = 1; fill_combined = c; fill_vmid = vm; fill_asid = as; fill_global = g; fill_page = pg; fill_pa = p;
    @(negedge clk); fill = 0;
  endtask
  task automatic inv(input [1:0] op, input [15:0] vm, input [15:0] as, input [35:0] pg);
    @(negedge clk); tlbi = 1; tlbi_op = op; tlbi_vmid = vm; tlbi_asid = as; tlbi_page = pg;
    @(negedge clk); tlbi = 0;
  endtask
  task automatic expect_hit(input bit c, input [15:0] vm, input [15:0] as, input [35:0] pg, input bit hit, input string what);
    lk_combined = c; lk_vmid = vm; lk_asid = as; lk_page = pg; #1;
    if (lk_hit !== hit) begin $display("FAIL %s", what); errors++; end
  endtask
  task automatic load;
    put(0, 16'd1, 16'd0, 0, 36'h000040000, 36'h000080000);   // S2 entry, VM 1
    put(1, 16'd1, 16'd5, 0, 36'h000000123, 36'h000080000);   // combined, VM 1, ASID 5
    put(1, 16'd1, 16'd0, 1, 36'h000000456, 36'h000080001);   // combined, global
    put(1, 16'd2, 16'd5, 0, 36'h000000123, 36'h0000a0000);   // combined, VM 2
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    load;
    expect_hit(1, 16'd1, 16'd5, 36'h123, 1, "combined hit");
    expect_hit(1, 16'd1, 16'd6, 36'h123, 0, "other ASID misses");
    expect_hit(1, 16'd1, 16'd9, 36'h456, 1, "global hits any ASID");
    expect_hit(0, 16'd2, 16'd0, 36'h40000, 0, "other VMID misses");

    inv(2'd0, 16'd1, 16'd0, 36'h40000);                      // IPAS2E1IS
    expect_hit(0, 16'd1, 16'd0, 36'h40000, 0, "IPAS2 removes the stage 2 entry");
    expect_hit(1, 16'd1, 16'd5, 36'h123, 1, "IPAS2 leaves the combined entry");

    inv(2'd1, 16'd1, 16'd0, 36'h0);                          // VMALLE1IS
    expect_hit(1, 16'd1, 16'd5, 36'h123, 0, "VMALLE1 removes combined");
    expect_hit(1, 16'd2, 16'd5, 36'h123, 1, "VMALLE1 leaves other VMID");

    load;
    inv(2'd1, 16'd1, 16'd0, 36'h0);
    expect_hit(0, 16'd1, 16'd0, 36'h40000, 1, "VMALLE1 leaves stage 2 entry");
    inv(2'd2, 16'd1, 16'd0, 36'h0);                          // VMALLS12E1IS
    expect_hit(0, 16'd1, 16'd0, 36'h40000, 0, "VMALLS12 removes stage 2");

    load;
    inv(2'd3, 16'd1, 16'd6, 36'h123);                        // VAE1IS other ASID
    expect_hit(1, 16'd1, 16'd5, 36'h123, 1, "VAE1 other ASID survives");
    inv(2'd3, 16'd1, 16'd5, 36'h123);
    expect_hit(1, 16'd1, 16'd5, 36'h123, 0, "VAE1 same ASID removes");
    inv(2'd3, 16'd1, 16'd7, 36'h456);
    expect_hit(1, 16'd1, 16'd0, 36'h456, 0, "VAE1 removes global entry");

    if (errors == 0) $display("PASS tb_s2_tlb"); else $display("FAIL tb_s2_tlb (%0d)", errors);
    $finish;
  end
endmodule
