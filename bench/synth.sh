#!/usr/bin/env bash
# Yosys synth_ecp5, then nextpnr place and route out of context (no IO
# buffers) on a Lattice LFE5U-25F, seed 1, for post route Fmax. Open tools only.
set -euo pipefail
cd "$(dirname "$0")/.."
out=bench/results; mkdir -p "$out"
printf "module,LUT4,FF,CCU2C carry,fmax_mhz\n" > "$out/synth_ecp5.csv"
for spec in s2_walker:rtl/s2_walker.sv s2_tlb:rtl/s2_tlb.sv; do
  top=${spec%%:*}; src=${spec##*:}
  yosys -q -p "read_verilog -sv $src; synth_ecp5 -top $top -json $out/$top.json; tee -q -o $out/$top.stat stat" >/dev/null
  lut=$(awk '/LUT4/{v=$2} END{print v+0}' "$out/$top.stat")
  ff=$(awk '/TRELLIS_FF/{v=$2} END{print v+0}' "$out/$top.stat")
  cc=$(awk '/CCU2C/{v=$2} END{print v+0}' "$out/$top.stat")
  fmax=n/a
  if command -v nextpnr-ecp5 >/dev/null; then
    nextpnr-ecp5 --25k --package CABGA381 --out-of-context --json "$out/$top.json" --freq 100 --seed 1 > "$out/$top.pnr" 2>&1 || true
    f=$(grep "Max frequency for clock" "$out/$top.pnr" | tail -1 | grep -oE "[0-9]+\.[0-9]+ MHz" | head -1 | cut -d' ' -f1 || true)
    fmax=${f:-"no reg to reg path"}
  fi
  echo "$top,$lut,$ff,$cc,$fmax" >> "$out/synth_ecp5.csv"
  rm -f "$out/$top.json" "$out/$top.pnr" "$out/$top.stat"
done
cat "$out/synth_ecp5.csv"
