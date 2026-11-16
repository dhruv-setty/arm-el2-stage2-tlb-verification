# IATO v7: Stage 2 Translation and TLB Maintenance

IATO v7 is the Arm virtualisation component of the IATO series. It defines, verifies and implements Stage 2 address translation and TLB maintenance for a hypervisor executing at EL2: a Sail model serves as the normative reference, a TLA+ specification verifies the unmap sequence, and the SystemVerilog implementation is validated against the reference by automated cross check. It is not a complete hypervisor or MMU: coverage is limited to the scope listed below, and all results come from simulation and open tool synthesis, with no physical FPGA or silicon measurement. The companion repository, [IATO](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object), covers coherence, PCIe ordering and DMA; together the two repositories apply one method: state the required behaviour first, then design, verify and measure against it. All figures in this document are produced by `./scripts/check.sh` and `./bench/run.sh` at release v0.2.0, and CI repeats every check on each push and pull request.

The key words MUST, MUST NOT, SHALL, SHOULD and MAY in this document are to be interpreted as described in BCP 14 (RFC 2119 and RFC 8174).

## Scope

In scope:

- Stage 2 translation with a 4 KiB granule, 48 bit IPA and start level 0.
- Table, block and page descriptors; translation, access flag and permission faults.
- Stage 2 only and combined TLB entries tagged by VMID and ASID.
- TLBI IPAS2E1IS, VMALLE1IS, VMALLS12E1IS and VAE1IS.
- Unmap ordering for one IPA page across two cores.

Out of scope:

- 16 KiB and 64 KiB granules, and concatenated start tables.
- Hardware access flag and dirty state update (FEAT_HAFDBS).
- Stage 1 translation, which is modelled only as a source of combined entries.
- Range TLBI operations and FEAT_TLBIOS variants.
- Multi page unmap, and break before make on live remapping.

Known limitations:

- All results come from simulation and open tool synthesis. No physical FPGA or silicon measurement has been performed.
- The TLA+ model covers one IPA page and two cores. It does not model memory ordering beyond DSB completion.
- The walker and TLB are synthesised as separate blocks. Integrated timing has not been measured.
- Synthesis figures are open tool estimates on a small FPGA. They are not vendor tool or ASIC figures.

Architectural behaviour follows ARM DDI 0487K. Sources are listed in [docs/references.md](docs/references.md).

Planned work (not implemented):

1. Cross check the walker and TLBI scopes against a QEMU TCG guest at EL2.
2. Overlap walks and cache level 0 to 2 descriptors, then measure the gain at latency 32.
3. Support concatenated start tables and a 40 bit IPA with start level 1.
4. Implement hardware access flag and dirty state update (FEAT_HAFDBS).
5. Integrate the walker, TLB and TLBI unit, then synthesise them as one block.

### Requirement identifiers

Each requirement carries an identifier, such as `S2-W-03`. Each requirement maps to at least one automated check, listed in the "Verified by" column of its table.

### Architecture

```
   guest (EL1)                    hypervisor (EL2)                   verified by
  -------------                  ------------------                 -------------
  VA --stage 1--> IPA
                   |
                   v
           +---------------+  miss   +----------------+  4 reads   +-------------------+
           | s2_tlb.sv     |-------> | s2_walker.sv   |----------> | Stage 2 tables    |
           | S2 only and   |  fill   | L0 L1 L2 L3    | <--------- | in memory         |
           | combined, by  | <------ | faults: trans, |   desc     | VTTBR_EL2 base    |
           | VMID and ASID |         | AF, permission |            +-------------------+
           +---------------+         +----------------+
                   ^                         |                     Sail stage2.sail
                   | TLBI IPAS2E1IS          v PA or fault         s2_vectors.py, s2_ref.c
                   | TLBI VMALLE1IS                                tb_s2_walker (Verilator)
                   | TLBI VMALLS12E1IS
                   | TLBI VAE1IS                                   Sail tlbi_scope.sail
                   |                                               tb_s2_tlb (Icarus)
           +------------------------------------------------+
           | unmap: clear desc, DSB, IPAS2E1IS, DSB,        |      S2Unmap.tla
           |        VMALLE1IS, DSB, free frame              |      three configurations
           +------------------------------------------------+
```

### Stage 2 walker requirements

| ID | Requirement | Verified by |
|---|---|---|
| S2-W-01 | The walker SHALL resolve a 48 bit IPA from the VTTBR_EL2 base in at most four levels, indexing nine IPA bits per level. | Walker cross check |
| S2-W-02 | The walker SHALL raise a translation fault, with its level, on an invalid descriptor. | Walker cross check |
| S2-W-03 | The walker SHALL treat a block descriptor at level 0, and descriptor type 0b01 at level 3, as reserved and raise a translation fault. | Walker cross check |
| S2-W-04 | The walker SHALL raise an access flag fault when AF is clear. It SHALL NOT update AF. | Walker cross check |
| S2-W-05 | The walker SHALL grant reads only when S2AP[0] is set, and writes only when S2AP[1] is set. Otherwise it SHALL raise a permission fault. | Walker cross check, planted fault |
| S2-W-06 | The walker SHALL return the same result encoding as the Sail reference: bit 63 fault, bits 62 to 60 kind, bits 59 to 58 level, bits 47 to 0 output address. | Walker cross check |

The probe generator, `tools/s2_vectors.py`, builds random tables with pages, 2 MiB blocks, 1 GiB blocks, invalid descriptors, reserved descriptors, AF clear and every S2AP value. It then probes addresses inside and outside each mapping. The Sail reference, the Python walker and the RTL MUST agree on every probe.

### Unmap sequence requirements

| ID | Requirement | Verified by |
|---|---|---|
| S2-U-01 | A hypervisor removing an IPA page from a guest SHALL clear the descriptor, issue DSB, issue TLBI IPAS2E1IS, issue DSB, issue TLBI VMALLE1IS and issue DSB before it frees the frame. | `S2Unmap` |
| S2-U-02 | The hypervisor SHALL NOT omit TLBI VMALLE1IS. TLBI IPAS2E1IS does not remove combined entries. | `S2Unmap_no_vmalle1` |
| S2-U-03 | The hypervisor SHALL NOT issue TLBI VMALLE1IS before TLBI IPAS2E1IS has completed. A core can refill a combined entry from a cached Stage 2 entry in between. | `S2Unmap_vmalle1_first` |

The model contains two cores. Each core can cache a Stage 2 entry and a combined entry, and can refill a combined entry from a cached Stage 2 entry without reading the tables. Broadcast TLBIs complete at the next DSB. The safety property `NoUseAfterFree` states that no guest access reaches the frame after it is freed.

| Configuration | Sequence | Result |
|---|---|---|
| `S2Unmap` | clear, DSB, IPAS2E1IS, DSB, VMALLE1IS, DSB, free | Holds, 74 states |
| `S2Unmap_no_vmalle1` | clear, DSB, IPAS2E1IS, DSB, free | Violated: a combined entry survives the free |
| `S2Unmap_vmalle1_first` | clear, DSB, VMALLE1IS, DSB, IPAS2E1IS, DSB, free | Violated: a combined entry is refilled after VMALLE1IS |

Instruction order is therefore a correctness requirement, not an optimisation.

### TLBI scope requirements

| ID | Operation | The TLB SHALL remove |
|---|---|---|
| S2-T-01 | IPAS2E1IS | Stage 2 only entries of the VMID for the IPA page |
| S2-T-02 | VMALLE1IS | Combined entries of the VMID |
| S2-T-03 | VMALLS12E1IS | All entries of the VMID |
| S2-T-04 | VAE1IS | Combined entries of the VMID for the VA page, with a matching ASID or the global attribute |
| S2-T-05 | Any operation | No entry of any other VMID |

Lookups SHALL match on VMID. Combined lookups SHALL also match on ASID unless the entry is global. The Sail definition and `s2_tlb.sv` are verified against the same cases.

### Repository layout

```
spec/sail/       stage2.sail, tlbi_scope.sail, checks.sail, main.sail
spec/tla/        S2Unmap.tla and three configurations
rtl/             s2_walker.sv, s2_tlb.sv
rtl/tb/          tb_s2_tlb.sv (Icarus)
sim/             tb_s2_walker.cpp (Verilator), s2_ref.c (Sail harness)
tools/           s2_vectors.py
bench/           run.sh, synth.sh, results/
scripts/         check.sh, build_sim.sh
docs/            references.md, RESULTS.md
```

### Version history

| Version | Content |
|---|---|
| v0.2.0 | Stage 2 reference model, unmap verification, walker and TLB implementation, cross check and synthesis |
| v0.1.0 | Lean 4 specification review against DDI 0487K, DDI 0608A, KVM and QEMU. Preserved at tag `archive/lean-v0.1.0` |

## Requirements

- Java 11 or later (CI uses Temurin 21), for TLC.
- Python 3.
- Sail 0.20 with libgmp (CI uses Sail 0.20.3).
- A C compiler.
- Icarus Verilog and Verilator.
- Optional: Yosys and nextpnr-ecp5, which enable synthesis.

CI installs these on `ubuntu-24.04`; see [.github/workflows/check.yml](.github/workflows/check.yml). Other platforms have not been tested.

## Build

`scripts/build_sim.sh` compiles the Sail reference to C (`build/s2_ref`, `build/sail_checks`) and builds the Verilator walker harness (`build/obj_w/tb_s2_walker`). `scripts/check.sh` and `bench/run.sh` call it, so a separate build step is not required. If `tools/tla2tools.jar` is absent, `scripts/check.sh` downloads TLA+ tools v1.8.0 into `tools/`.

## Usage

```
./scripts/check.sh    # model checking, Sail assertions, cross check, RTL tests, synthesis
./bench/run.sh        # five seed cross check and latency sweep
./bench/synth.sh      # ECP5 synthesis only
```

`bench/run.sh` writes `bench/results/s2_walker.csv`. `bench/synth.sh` writes `bench/results/synth_ecp5.csv`.

## Configuration

- `TLA_JAR`: path to `tla2tools.jar` used by `scripts/check.sh`. The default is `tools/tla2tools.jar`.
- `tools/s2_vectors.py [seed] [probes]`: the defaults are seed 1 and 400 probes.
- `build/obj_w/tb_s2_walker [latency]`: memory latency in cycles; the default is 1.

## Verification and testing

`check.sh` exits non zero if any passing configuration fails, or if either incorrect unmap ordering fails to violate `NoUseAfterFree`. The synthesis step runs only when `yosys` is on the path. Full result tables are in [docs/RESULTS.md](docs/RESULTS.md).

### Verification summary

| Area | Artefact | Method | Result |
|---|---|---|---|
| Stage 2 reference | `spec/sail/stage2.sail` | Sail compiled to C | Reference for all walker checks |
| Walker conformance | `rtl/s2_walker.sv` | 10,000 random probes across five table sets, compared with Sail and an independent Python walker | 0 mismatches. A planted permission fault produces 330 mismatches in 2,000 probes |
| Unmap ordering | `spec/tla/S2Unmap.tla` | TLC model checking, three configurations | The required sequence holds over 74 states. Both incorrect orderings violate `NoUseAfterFree` |
| TLBI scope | `spec/sail/tlbi_scope.sail`, `rtl/s2_tlb.sv` | 8 Sail assertions, 13 directed RTL checks | Pass |
| Synthesis | `bench/synth.sh` | Yosys and nextpnr, Lattice ECP5 LFE5U-25F | Walker 370 LUT4 at 236.57 MHz. 8 entry TLB 3,246 LUT4 at 136.72 MHz |

### Walk latency

The walker holds one table read in flight. A full walk costs 1 + 4 x (latency + 1) cycles.

| Memory latency (cycles) | Mean cycles per walk, all probes | Four level walk |
|---|---|---|
| 1 | 6.22 | 9 cycles |
| 8 | 24.49 | 37 cycles |
| 32 | 87.11 | 133 cycles |

Seed 1, 2,000 probes. The mean is lower than the four level figure because most faulting probes terminate at an early level.

### Synthesis

Yosys `synth_ecp5`, then nextpnr out of context on a Lattice LFE5U-25F, seed 1.

| Module | LUT4 | FF | Carry | Post route Fmax |
|---|---|---|---|---|
| s2_walker | 370 | 143 | 0 | 236.57 MHz |
| s2_tlb | 3,246 | 859 | 0 | 136.72 MHz |

The TLB implements a fully associative compare across eight entries with four TLBI match rules, which accounts for most of its logic.

## Security

Commit verification and vulnerability reporting are described in [SECURITY.md](SECURITY.md); the maintainer signing key is in [KEYS.asc](KEYS.asc).

## License

Apache License 2.0. See [LICENSE](LICENSE).
