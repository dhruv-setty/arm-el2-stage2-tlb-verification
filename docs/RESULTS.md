# IĀTŌ v7 results

Generated from `bench/results/` and `./scripts/check.sh`. Simulation and open tool synthesis; no physical FPGA, no vendor tools.

## Contents

1. [Model checking (TLC)](#1-model-checking-tlc)
2. [Executable specs and simulation](#2-executable-specs-and-simulation)
3. [Stage 2 walker cross check and latency](#3-stage-2-walker-cross-check-and-latency)
4. [Synthesis, Lattice ECP5](#4-synthesis-lattice-ecp5)

## 1. Model checking (TLC)

| Config | Sequence | Result | Distinct states |
|---|---|---|---|
| S2Unmap | correct sequence | NoUseAfterFree holds | 74 |
| S2Unmap_no_vmalle1 | no VMALLE1IS | violated, as expected | 74 |
| S2Unmap_vmalle1_first | VMALLE1IS before IPAS2E1IS | violated, as expected | 91 |

## 2. Executable specs and simulation

| Check | Tool | Scope | Result |
|---|---|---|---|
| Sail tlbi_scope | Sail 0.20.3 to C | 8 assertions | pass |
| Sail stage2 vs Python walker | Sail to C | 10,000 probes, 5 seeds | 0 mismatches |
| s2_walker vs vectors | Verilator | 10,000 probes at 3 latencies | 0 mismatches |
| s2_walker, permission bits swapped | Verilator | 2,000 probes, seed 1 | 330 mismatches (bug caught) |
| tb_s2_tlb | Icarus | 13 directed checks | pass |

## 3. Stage 2 walker cross check and latency

| Seed | Latency | Probes | Translations | Translation faults | AF faults | Permission faults | Sail mismatches | RTL mismatches | Cycles per walk | Reads per walk | Four level walks | Four level cycles |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 2,000 | 505 | 1074 | 74 | 347 | 0 | 0 | 6.22 | 2.61 | 512 | 9.00 |
| 1 | 8 | 2,000 | 505 | 1074 | 74 | 347 | 0 | 0 | 24.49 | 2.61 | 512 | 37.00 |
| 1 | 32 | 2,000 | 505 | 1074 | 74 | 347 | 0 | 0 | 87.11 | 2.61 | 512 | 133.00 |
| 2 | 1 | 2,000 | 508 | 1076 | 69 | 347 | 0 | 0 | 6.14 | 2.57 | 460 | 9.00 |
| 2 | 8 | 2,000 | 508 | 1076 | 69 | 347 | 0 | 0 | 24.14 | 2.57 | 460 | 37.00 |
| 2 | 32 | 2,000 | 508 | 1076 | 69 | 347 | 0 | 0 | 85.84 | 2.57 | 460 | 133.00 |
| 3 | 1 | 2,000 | 535 | 1069 | 88 | 308 | 0 | 0 | 6.16 | 2.58 | 489 | 9.00 |
| 3 | 8 | 2,000 | 535 | 1069 | 88 | 308 | 0 | 0 | 24.23 | 2.58 | 489 | 37.00 |
| 3 | 32 | 2,000 | 535 | 1069 | 88 | 308 | 0 | 0 | 86.17 | 2.58 | 489 | 133.00 |
| 4 | 1 | 2,000 | 535 | 1080 | 71 | 314 | 0 | 0 | 6.22 | 2.61 | 521 | 9.00 |
| 4 | 8 | 2,000 | 535 | 1080 | 71 | 314 | 0 | 0 | 24.50 | 2.61 | 521 | 37.00 |
| 4 | 32 | 2,000 | 535 | 1080 | 71 | 314 | 0 | 0 | 87.16 | 2.61 | 521 | 133.00 |
| 5 | 1 | 2,000 | 473 | 1088 | 84 | 355 | 0 | 0 | 6.20 | 2.60 | 492 | 9.00 |
| 5 | 8 | 2,000 | 473 | 1088 | 84 | 355 | 0 | 0 | 24.41 | 2.60 | 492 | 37.00 |
| 5 | 32 | 2,000 | 473 | 1088 | 84 | 355 | 0 | 0 | 86.85 | 2.60 | 492 | 133.00 |

## 4. Synthesis, Lattice ECP5

Yosys `synth_ecp5`, nextpnr out of context on LFE5U-25F, seed 1.

| Module | LUT4 | FF | Carry (CCU2C) | Post route Fmax |
|---|---|---|---|---|
| s2_walker | 370 | 143 | 0 | 236.57 MHz |
| s2_tlb | 3,246 | 859 | 0 | 136.72 MHz |
