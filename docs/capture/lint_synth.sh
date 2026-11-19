#!/usr/bin/env bash
# Verilator lint with the flags used by scripts/check.sh, then ECP5 synthesis and
# place and route through bench/synth.sh.
set -uo pipefail
cd "$(dirname "$0")/../.."
verilator --version
for f in rtl/s2_walker.sv rtl/s2_tlb.sv; do
  echo "\$ verilator --lint-only -Wall -Wno-UNUSEDSIGNAL $f"
  verilator --lint-only -Wall -Wno-UNUSEDSIGNAL "$f" && echo "ok    lint $f"
done
echo "\$ yosys -V"; yosys -V
echo "\$ nextpnr-ecp5 --version"; nextpnr-ecp5 --version 2>&1 | head -1
echo "\$ bench/synth.sh"; bench/synth.sh
