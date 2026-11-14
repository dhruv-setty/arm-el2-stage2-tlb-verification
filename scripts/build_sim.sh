#!/usr/bin/env bash
# Builds the Sail reference (Sail to C) and the Verilator walker harness.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
L=$(sail -dir)/lib
sail -c --c-no-main --c-preserve s2_translate spec/sail/stage2.sail spec/sail/tlbi_scope.sail \
  spec/sail/checks.sail spec/sail/main.sail -o build/s2_sail
gcc -O1 -include sim/read_pt.h build/s2_sail.c sim/s2_ref.c "$L"/*.c -I"$L" -lgmp -lz -o build/s2_ref
sail -c spec/sail/stage2.sail spec/sail/tlbi_scope.sail spec/sail/checks.sail spec/sail/main.sail -o build/sail_checks
gcc -O1 -include sim/read_pt.h build/sail_checks.c sim/read_pt_stub.c "$L"/*.c -I"$L" -lgmp -lz -o build/sail_checks
rm -f sail_smt_cache
rm -rf build/obj_w
verilator -Wall -Wno-UNUSEDSIGNAL --cc --exe --build -O2 --Mdir build/obj_w rtl/s2_walker.sv sim/tb_s2_walker.cpp -o tb_s2_walker >/dev/null
