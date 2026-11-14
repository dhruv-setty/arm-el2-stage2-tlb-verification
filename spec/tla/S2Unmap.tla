------------------------------ MODULE S2Unmap ------------------------------
(* A hypervisor takes one IPA page away from a guest and frees the frame.   *)
(* Cores cache two kinds of entry (ARM DDI 0487K, TLB maintenance): stage 2 *)
(* only (IPA to PA) and combined (VA to PA through that IPA). A combined    *)
(* entry can be refilled from a cached stage 2 entry without reading the    *)
(* tables, and TLBI IPAS2E1IS does not remove combined entries. The         *)
(* hypervisor runs one of the sequences in Steps; broadcast TLBIs complete  *)
(* at the next DSB, and the cleared descriptor reaches the walkers at a DSB *)
EXTENDS Naturals, Sequences

CONSTANTS Cores, Mode   \* Mode: "correct", "no_vmalle1", "vmalle1_first"

Steps ==
  CASE Mode = "correct"       -> <<"clear", "dsb", "ipas2", "dsb", "vmalle1", "dsb", "free">>
    [] Mode = "no_vmalle1"    -> <<"clear", "dsb", "ipas2", "dsb", "free">>
    [] Mode = "vmalle1_first" -> <<"clear", "dsb", "vmalle1", "dsb", "ipas2", "dsb", "free">>

VARIABLES pte, pteHyp, tlb, pend, pc, freed, bad
vars == <<pte, pteHyp, tlb, pend, pc, freed, bad>>

Init ==
  /\ pte = TRUE /\ pteHyp = TRUE           \* stage 2 descriptor valid
  /\ tlb = [c \in Cores |-> {}]             \* subset of {"S2", "CB"}
  /\ pend = {}                               \* TLBIs issued, not yet complete
  /\ pc = 1 /\ freed = FALSE /\ bad = FALSE

Remove(e, ops) ==
  e \ ((IF "ipas2" \in ops THEN {"S2"} ELSE {}) \cup (IF "vmalle1" \in ops THEN {"CB"} ELSE {}))

Hyp ==
  /\ pc <= Len(Steps)
  /\ LET s == Steps[pc] IN
       CASE s = "clear"   -> pteHyp' = FALSE /\ UNCHANGED <<pte, tlb, pend, freed>>
         [] s = "dsb"     -> /\ pte' = pteHyp
                             /\ tlb' = [c \in Cores |-> Remove(tlb[c], pend)]
                             /\ pend' = {}
                             /\ UNCHANGED <<pteHyp, freed>>
         [] s = "free"    -> freed' = TRUE /\ UNCHANGED <<pte, pteHyp, tlb, pend>>
         [] OTHER         -> pend' = pend \cup {s} /\ UNCHANGED <<pte, pteHyp, tlb, freed>>
  /\ pc' = pc + 1
  /\ UNCHANGED bad

\* A walk reads the descriptor as the walkers see it.
FillS2(c) == pte /\ tlb' = [tlb EXCEPT ![c] = @ \cup {"S2"}] /\ UNCHANGED <<pte, pteHyp, pend, pc, freed, bad>>
FillCB(c) == (pte \/ "S2" \in tlb[c]) /\ tlb' = [tlb EXCEPT ![c] = @ \cup {"CB"}]
             /\ UNCHANGED <<pte, pteHyp, pend, pc, freed, bad>>

\* A guest access reaches the frame through any route that is still open.
Access(c) ==
  /\ pte \/ tlb[c] # {}
  /\ bad' = (bad \/ freed)
  /\ UNCHANGED <<pte, pteHyp, tlb, pend, pc, freed>>

Done == pc > Len(Steps) /\ UNCHANGED vars
Next == Done \/ Hyp \/ \E c \in Cores : FillS2(c) \/ FillCB(c) \/ Access(c)
Spec == Init /\ [][Next]_vars

NoUseAfterFree == ~bad
=============================================================================
