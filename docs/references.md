# References

Cited by name and section. No specification text is copied into this repo.

| Reference | Used for |
|---|---|
| ARM DDI 0487K, Arm Architecture Reference Manual for A-profile, VMSAv8-64 translation table format | Stage 2 descriptor layout: type bits, S2AP, AF, output address fields; 4 KiB granule, levels 0 to 3 |
| ARM DDI 0487K, VTCR_EL2 and VTTBR_EL2 | T0SZ 16 for a 48 bit IPA, start level 0, table base |
| ARM DDI 0487K, TLB maintenance instructions | Scope of TLBI IPAS2E1IS, VMALLE1IS, VMALLS12E1IS, VAE1IS; combined stage 1 and stage 2 entries; the IPAS2, DSB, VMALLE1, DSB sequence |
| ARM DDI 0608A, Armv9-A supplement | Context for the Armv9 cores the walker targets |
| Arm Neoverse N2 and V3 Technical Reference Manuals | Context only; no core specific TLB sizes are modelled |
| Linux KVM arm64 (`arch/arm64/kvm`, docs.kernel.org/virt/kvm) | How a hypervisor unmaps guest memory, as the shape of the S2Unmap sequence |
| QEMU `target/arm` | Planned cross check of the walker and TLBI scopes against a TCG guest at EL2 |
| Sail 0.20.3 (rems-project/sail) | Specification language and C backend used as the reference model |
