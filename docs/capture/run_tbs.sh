#!/usr/bin/env bash
# Runs the two RTL testbenches as CI does: the Icarus Verilog TLB testbench (with a
# VCD dump added by a separate wrapper module, so neither the RTL nor the testbench
# changes) and the Verilator walker harness against Sail-checked vectors at three
# memory latencies. Expects ./scripts/build_sim.sh to have been run.
set -uo pipefail
cd "$(dirname "$0")/../.."
out=${OUT:-build/capture}; mkdir -p "$out"
fail=0
iverilog -V 2>&1 | head -1
tb=tb_s2_tlb
printf 'module dump_%s; initial begin $dumpfile("%s/%s.vcd"); $dumpvars(0, %s); end endmodule\n' "$tb" "$out" "$tb" "$tb" > "$out/dump_$tb.sv"
echo "\$ iverilog -g2012 -s $tb -o $tb.vvp rtl/tb/$tb.sv rtl/s2_tlb.sv"
iverilog -g2012 -s "$tb" -s "dump_$tb" -o "$out/$tb.vvp" "rtl/tb/$tb.sv" rtl/s2_tlb.sv "$out/dump_$tb.sv" || fail=1
echo "\$ vvp $tb.vvp"
vvp -n "$out/$tb.vvp" | grep -v "^VCD info" | tee "$out/$tb.out"
grep -q "^PASS" "$out/$tb.out" || fail=1
verilator --version
echo "\$ python3 tools/s2_vectors.py 1 2000"
python3 tools/s2_vectors.py 1 2000 || fail=1
echo "\$ build/s2_ref"
build/s2_ref || fail=1
for lat in 1 8 32; do
  echo "\$ build/obj_w/tb_s2_walker $lat"
  build/obj_w/tb_s2_walker "$lat" || fail=1
done
echo "exit status $fail"
exit $fail
