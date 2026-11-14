# IĀTŌ v7

[![check](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object-v7/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object-v7/actions/workflows/check.yml)
![release](https://img.shields.io/badge/release-v0.2.0-blue)
![license](https://img.shields.io/badge/license-Apache%202.0-blue)
![Sail](https://img.shields.io/badge/spec-Sail-259dd5)
![TLA+](https://img.shields.io/badge/spec-TLA%2B-4b6cb7)
![RTL](https://img.shields.io/badge/RTL-SystemVerilog-b2b7f8)
![FPGA](https://img.shields.io/badge/ECP5-236.57%20MHz%20walker-success)
![vectors](https://img.shields.io/badge/cross%20check-10%2C000%20probes%2C%200%20mismatches-success)

**The Arm piece of the IĀTŌ series.** Stage 2 translation and TLB maintenance for a hypervisor at EL2, written as a Sail reference model, checked in TLA+, built as Verilog, and tested against the model.

The main [IĀTŌ](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object) repo covers coherence, PCIe and DMA. This one covers what happens between a guest's physical address and the real one: how a Stage 2 walk reads four levels of tables, which faults it raises, and which TLB entries survive which TLBI. Every number below comes from `./scripts/check.sh` or `./bench/run.sh`, and CI repeats the checks on every push.

## Contents

1. [Results at a glance](#1-results-at-a-glance)
2. [System](#2-system)
3. [Stage 2 walker](#3-stage-2-walker)
4. [Unmapping a guest page](#4-unmapping-a-guest-page)
5. [TLBI scopes](#5-tlbi-scopes)
6. [Synthesis](#6-synthesis)
7. [Layout](#7-layout)
8. [Roadmap](#8-roadmap)
9. [History](#9-history)
10. [License](#10-license)

## 1. Results at a glance

| Area | Artefact | Result |
|---|---|---|
| Stage 2 model | `spec/sail/stage2.sail` | 4 KiB granule, 48 bit IPA, start level 0. Table, block (1 GiB, 2 MiB) and page descriptors; translation, access flag and permission faults with the level they occur at. Compiled to C and used as the reference |
| Cross check | `tools/s2_vectors.py`, `sim/s2_ref.c`, `sim/tb_s2_walker.cpp` | 10,000 probes over five random table sets: Sail, an independent Python walker and the RTL agree on every one, 2,556 translations and the rest faults |
| Walker RTL | `rtl/s2_walker.sv` | One table read in flight. A four level walk takes 9 cycles at memory latency 1 and 133 at latency 32 |
| Unmap sequence | `spec/tla/S2Unmap.tla` | Clear, DSB, TLBI IPAS2E1IS, DSB, TLBI VMALLE1IS, DSB, free holds over 74 states. Dropping VMALLE1IS, or issuing it before IPAS2E1IS, lets a guest reach a freed frame |
| TLBI scopes | `spec/sail/tlbi_scope.sail`, `rtl/s2_tlb.sv` | Stage 2 only and combined entries tagged by VMID and ASID; four TLBI scopes; 8 Sail assertions and 13 directed RTL checks pass |
| Synthesis | `bench/synth.sh` | ECP5: walker 370 LUT4 at 236.57 MHz, 8 entry TLB 3,246 LUT4 at 136.72 MHz |

## 2. System

```
   guest (EL1)                    hypervisor (EL2)                   checked by
  -------------                  ------------------                 ------------
  VA --stage 1--> IPA
                   |
                   v
           +---------------+  miss   +----------------+  4 reads   +-------------------+
           | s2_tlb.sv     |-------> | s2_walker.sv   |----------> | stage 2 tables    |
           | S2 only and   |  fill   | L0 L1 L2 L3    | <--------- | in memory         |
           | combined, by  | <------ | faults: trans, |   desc     | VTTBR_EL2 base    |
           | VMID and ASID |         | AF, permission |            +-------------------+
           +---------------+         +----------------+
                   ^                         |                     Sail stage2.sail
                   | TLBI IPAS2E1IS          v PA or fault         s2_vectors.py + s2_ref.c
                   | TLBI VMALLE1IS                                tb_s2_walker (Verilator)
                   | TLBI VMALLS12E1IS
                   | TLBI VAE1IS                                   Sail tlbi_scope.sail
                   |                                               tb_s2_tlb (Icarus)
           +------------------------------------------------+
           | unmap: clear desc, DSB, IPAS2E1IS, DSB,        |      S2Unmap.tla
           |        VMALLE1IS, DSB, free frame              |      3 configs
           +------------------------------------------------+
```

Full tables for every run are in [docs/RESULTS.md](docs/RESULTS.md).

## 3. Stage 2 walker

The walker takes VTTBR_EL2's base, an IPA and read or write. Each level indexes nine bits of the IPA, reads one descriptor, and either follows a table, stops at a block or page, or faults. A block at level 0 and type 0b01 at level 3 are reserved and fault as translation faults. AF clear faults (no hardware update), and S2AP decides read and write. The result word carries the fault kind and level or the output address, the same encoding the Sail model returns.

**Cross check.** `tools/s2_vectors.py` builds random tables with pages, 2 MiB and 1 GiB blocks, invalid and reserved descriptors, AF clear and every S2AP value, then probes inside and outside the mappings. The Sail model, the Python walker and the RTL must agree on every probe. A deliberate bug that swaps the read and write permission bits in the RTL shows up as 330 mismatches in 2,000 probes.

| Memory latency | Cycles per walk, all probes | Four level walk |
|---|---|---|
| 1 | 6.22 | 9 cycles |
| 8 | 24.49 | 37 cycles |
| 32 | 87.11 | 133 cycles |

Seed 1, 2,000 probes. A walk costs one cycle to accept plus one issue cycle and the latency per level, so a full walk is 1 + 4 x (latency + 1). Most probes fault early, which is why the average is lower. Overlapping walks, or caching upper levels, is the next step.

## 4. Unmapping a guest page

`S2Unmap.tla` has two cores that can cache a stage 2 entry for the page and a combined entry for the guest VA that maps to it, and can refill a combined entry from a cached stage 2 entry without reading the tables. Broadcast TLBIs complete at the next DSB.

| Sequence | Result |
|---|---|
| clear, DSB, IPAS2E1IS, DSB, VMALLE1IS, DSB, free | holds, 74 states |
| clear, DSB, IPAS2E1IS, DSB, free | a combined entry survives and reaches the freed frame |
| clear, DSB, VMALLE1IS, DSB, IPAS2E1IS, DSB, free | a core refills a combined entry from its stage 2 entry after VMALLE1IS, and keeps it past the free |

The order matters, not just the set of TLBIs.

## 5. TLBI scopes

| TLBI | Removes |
|---|---|
| IPAS2E1IS | Stage 2 only entries of the VMID for that IPA page |
| VMALLE1IS | Combined entries of the VMID |
| VMALLS12E1IS | Every entry of the VMID |
| VAE1IS | Combined entries of the VMID for that VA page, matching ASID or global |

Other VMIDs are never touched. The Sail definition and `s2_tlb.sv` are checked against the same cases.

## 6. Synthesis

Yosys `synth_ecp5`, then nextpnr out of context on a Lattice LFE5U-25F, seed 1. Open tool estimates on a small FPGA, not vendor or ASIC numbers.

| Module | LUT4 | FF | Carry | Post route Fmax |
|---|---|---|---|---|
| s2_walker | 370 | 143 | 0 | 236.57 MHz |
| s2_tlb | 3,246 | 859 | 0 | 136.72 MHz |

The TLB is a flat compare across eight entries with four TLBI match rules, which is where the LUTs go.

## 7. Layout

```
spec/sail/       stage2.sail, tlbi_scope.sail, checks.sail, main.sail
spec/tla/        S2Unmap.tla and three configs
rtl/             s2_walker.sv, s2_tlb.sv
rtl/tb/          tb_s2_tlb.sv (Icarus)
sim/             tb_s2_walker.cpp (Verilator), s2_ref.c (Sail harness)
tools/           s2_vectors.py
bench/           run.sh, synth.sh, results/
scripts/         check.sh, build_sim.sh
docs/            references.md, RESULTS.md
```

Requirements: Java 11 or later, Python 3, Sail 0.20 with libgmp, a C compiler, Icarus Verilog, Verilator, and optionally Yosys and nextpnr-ecp5.

## 8. Roadmap

1. QEMU: run the same tables in a TCG guest at EL2 and compare faults and output addresses with the Sail model.
2. Walker: overlap walks and cache level 0 to 2 descriptors; measure the gain at latency 32.
3. Concatenated start tables and a 40 bit IPA (start level 1), as KVM commonly uses.
4. Hardware access flag and dirty state update (FEAT_HAFDBS).
5. Join the walker, TLB and TLBI unit into one block and synthesise it together.

## 9. History

The v0.1.0 Lean 4 specification review, with its findings against DDI0487K, DDI0608A, KVM, QEMU and Cobalt documentation, is preserved at the tag `archive/lean-v0.1.0`.

## 10. License

Apache 2.0. See `LICENSE`.
