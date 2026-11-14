/* Which TLB entries a broadcast TLBI removes, after ARM DDI 0487K, TLB
   maintenance instructions. Two kinds of entry are cached: stage 2 only
   (IPA to PA) and combined stage 1 plus stage 2 (VA to PA). The point the
   repo's TLA+ model checks: IPAS2E1IS leaves combined entries in place. */

enum EntryKind = { S2Only, Combined }

struct Entry = {
  kind   : EntryKind,
  vmid   : bits(16),
  asid   : bits(16),
  global : bool,
  page   : bits(36),   /* IPA[47:12] for S2Only, VA[47:12] for Combined */
}

enum TLBIOp = { IPAS2E1IS, VMALLE1IS, VMALLS12E1IS, VAE1IS }

val is_s2 : EntryKind -> bool
function is_s2(k) = match k { S2Only => true, Combined => false }

val tlbi_hits : (TLBIOp, bits(16), bits(16), bits(36), Entry) -> bool
function tlbi_hits(op, vmid, asid, page, e) =
  let hit : bool = match op {
    IPAS2E1IS    => is_s2(e.kind) & e.page == page,
    VMALLE1IS    => not_bool(is_s2(e.kind)),
    VMALLS12E1IS => true,
    VAE1IS       => not_bool(is_s2(e.kind)) & e.page == page & (e.global | e.asid == asid),
  } in
  e.vmid == vmid & hit
