#!/usr/bin/env bash
# Runs every check. Passing configs must pass; the two broken unmap sequences
# must fail on NoUseAfterFree specifically.
set -uo pipefail
cd "$(dirname "$0")/.."
TLA_JAR="${TLA_JAR:-tools/tla2tools.jar}"
if [ ! -f "$TLA_JAR" ]; then
  mkdir -p tools
  curl -sSL -o "$TLA_JAR" https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
fi
TLA_JAR="$(cd "$(dirname "$TLA_JAR")" && pwd)/$(basename "$TLA_JAR")"
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

tlc() { # cfg expect(pass|violates)
  local out states
  out=$(cd spec/tla && java -XX:+UseParallelGC -cp "$TLA_JAR" tlc2.TLC -workers auto -cleanup -config "$1.cfg" S2Unmap.tla 2>&1)
  rm -rf spec/tla/states spec/tla/*_TTrace_* 2>/dev/null
  states=$(grep -oE "[0-9,]+ distinct states found" <<<"$out" | tail -1)
  if [ "$2" = pass ] && grep -q "No error has been found" <<<"$out"; then ok "TLC $1 (holds; $states)"
  elif [ "$2" = violates ] && grep -q "Invariant NoUseAfterFree is violated" <<<"$out"; then ok "TLC $1 (NoUseAfterFree violated as expected; $states)"
  else bad "TLC $1 expected $2"; fi
}
tlc S2Unmap               pass
tlc S2Unmap_no_vmalle1    violates
tlc S2Unmap_vmalle1_first violates

for f in rtl/s2_walker.sv rtl/s2_tlb.sv; do
  verilator --lint-only -Wall -Wno-UNUSEDSIGNAL "$f" >/dev/null 2>&1 && ok "lint $f" || bad "lint $f"
done

mkdir -p build
iverilog -g2012 -o build/tb_s2_tlb rtl/tb/tb_s2_tlb.sv rtl/s2_tlb.sv 2>/dev/null \
  && vvp -n build/tb_s2_tlb | grep -q "^PASS" && ok "sim tb_s2_tlb (TLBI scopes, VMID and ASID tagging)" || bad "sim tb_s2_tlb"

if ./scripts/build_sim.sh > build/build.log 2>&1; then
  build/sail_checks | grep -q "^PASS" && ok "sail tlbi scope (8 assertions)" || bad "sail tlbi scope"
  for seed in 1 2 3; do
    python3 tools/s2_vectors.py "$seed" 2000 >/dev/null
    build/s2_ref | grep -q "^PASS" && ok "sail stage 2 vs python walker, seed $seed, 2000 probes" || bad "sail stage 2 seed $seed"
    build/obj_w/tb_s2_walker 8 | grep -q "^PASS" && ok "rtl s2_walker vs sail vectors, seed $seed" || bad "rtl s2_walker seed $seed"
  done
  python3 tools/s2_vectors.py 1 400 >/dev/null
else
  tail -40 build/build.log; bad "build sail reference and walker harness"
fi

if command -v yosys >/dev/null; then
  ./bench/synth.sh >/dev/null 2>&1 && ok "yosys synth_ecp5" || bad "yosys synth_ecp5"
fi

if [ $fail -eq 0 ]; then echo "all expectations hold"; else echo "some checks failed"; exit 1; fi
