/* Executable checks for tlbi_scope.sail. The stage 2 walk is checked against
   the RTL with generated vectors (tools/s2_vectors.py, sim/s2_ref.c). */
val run_checks : unit -> unit
function run_checks() = {
  let s2 : Entry = struct { kind = S2Only,   vmid = 0x0001, asid = 0x0000, global = false, page = 0x000040000 };
  let cb : Entry = struct { kind = Combined, vmid = 0x0001, asid = 0x0005, global = false, page = 0x000000123 };
  let other_vm : Entry = struct { kind = Combined, vmid = 0x0002, asid = 0x0005, global = false, page = 0x000000123 };
  assert(tlbi_hits(IPAS2E1IS, 0x0001, 0x0000, 0x000040000, s2), "IPAS2 removes the stage 2 entry");
  assert(not_bool(tlbi_hits(IPAS2E1IS, 0x0001, 0x0000, 0x000040000, cb)), "IPAS2 leaves combined entries");
  assert(tlbi_hits(VMALLE1IS, 0x0001, 0x0000, 0x000000000, cb), "VMALLE1 removes combined entries");
  assert(not_bool(tlbi_hits(VMALLE1IS, 0x0001, 0x0000, 0x000000000, s2)), "VMALLE1 leaves stage 2 entries");
  assert(tlbi_hits(VMALLS12E1IS, 0x0001, 0x0000, 0x000000000, s2) & tlbi_hits(VMALLS12E1IS, 0x0001, 0x0000, 0x000000000, cb), "VMALLS12 removes both");
  assert(not_bool(tlbi_hits(VMALLS12E1IS, 0x0001, 0x0000, 0x000000000, other_vm)), "other VMID untouched");
  assert(tlbi_hits(VAE1IS, 0x0001, 0x0005, 0x000000123, cb), "VAE1 same ASID");
  assert(not_bool(tlbi_hits(VAE1IS, 0x0001, 0x0006, 0x000000123, cb)), "VAE1 other ASID survives");
  print_endline("PASS sail tlbi scope")
}
