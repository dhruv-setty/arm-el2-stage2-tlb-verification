/* AArch64 Stage 2 translation, 4 KiB granule, 48 bit IPA (VTCR_EL2.T0SZ 16,
   start level 0), after ARM DDI 0487K, VMSAv8-64 translation table format.
   Written for this repo, not copied from Arm's Sail model.

   Descriptor bits used: [1:0] type, [7:6] S2AP, [10] AF, [47:12] address.
   No hardware AF or dirty update, no concatenated start tables, no LPA2. */

default Order dec
$include <prelude.sail>

/* Page table memory is supplied by the harness that links the C output. */
val read_pt = impure {c: "read_pt"} : bits(64) -> bits(64)

/* Result word: [63] fault, [62:60] kind, [59:58] level, [47:0] output address. */
let FAULT_TRANSLATION : bits(3) = 0b001
let FAULT_ACCESS_FLAG : bits(3) = 0b010
let FAULT_PERMISSION  : bits(3) = 0b011

val lvl2 : int -> bits(2)
function lvl2(l) = match l { 0 => 0b00, 1 => 0b01, 2 => 0b10, _ => 0b11 }

val fault : (bits(3), int) -> bits(64)
function fault(kind, l) = 0b1 @ kind @ lvl2(l) @ 0x000000000000 @ 0b0000000000

val index_at : (int, bits(48)) -> bits(9)
function index_at(l, ipa) = match l {
  0 => ipa[47 .. 39],
  1 => ipa[38 .. 30],
  2 => ipa[29 .. 21],
  _ => ipa[20 .. 12],
}

/* S2AP[0] grants read, S2AP[1] grants write. */
val s2_perm_ok : (bits(64), bool) -> bool
function s2_perm_ok(d, write) =
  if write then d[7] == bitone else d[6] == bitone

val output_address : (int, bits(64), bits(48)) -> bits(48)
function output_address(l, d, ipa) = match l {
  1 => d[47 .. 30] @ ipa[29 .. 0],
  2 => d[47 .. 21] @ ipa[20 .. 0],
  _ => d[47 .. 12] @ ipa[11 .. 0],
}

val s2_translate : (bits(48), bits(48), bool) -> bits(64)
function s2_translate(vttbr, ipa, write) = {
  var table : bits(48) = vttbr[47 .. 12] @ 0x000;
  var level : int = 0;
  var result : bits(64) = 0x0000000000000000;
  var done : bool = false;
  while not_bool(done) do {
    let d = read_pt(0x0000 @ table[47 .. 12] @ index_at(level, ipa) @ 0b000);
    if d[0] == bitzero then {
      result = fault(FAULT_TRANSLATION, level); done = true
    } else if level < 3 & d[1] == bitone then {
      table = d[47 .. 12] @ 0x000; level = level + 1
    } else if level == 0 | (level == 3 & d[1] == bitzero) then {
      /* block at level 0 and type 0b01 at level 3 are reserved */
      result = fault(FAULT_TRANSLATION, level); done = true
    } else if d[10] == bitzero then {
      result = fault(FAULT_ACCESS_FLAG, level); done = true
    } else if not_bool(s2_perm_ok(d, write)) then {
      result = fault(FAULT_PERMISSION, level); done = true
    } else {
      result = 0x0000 @ output_address(level, d, ipa); done = true
    }
  };
  result
}
