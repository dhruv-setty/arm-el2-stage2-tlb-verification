#!/usr/bin/env python3
"""Random Stage 2 page tables and IPA probes for the walker cross check.

Writes build/s2_mem.txt (one "pa data" line per non zero table word) and
build/s2_vec.txt (one "vttbr ipa write expect" line per probe). The expected
word comes from the small Python walker below, which follows the same rules as
spec/sail/stage2.sail; sim/s2_ref.c then checks Sail against it and the RTL
testbench checks the RTL against it, so all three must agree."""
import random, sys, os

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 1
N = int(sys.argv[2]) if len(sys.argv) > 2 else 400
rng = random.Random(SEED)
VTTBR = 0x4000_0000
mem = {}
next_table = [VTTBR + 0x1000]
SHIFT = {0: 39, 1: 30, 2: 21, 3: 12}

def new_table():
    a = next_table[0]; next_table[0] += 0x1000; return a

def idx(l, ipa): return (ipa >> SHIFT[l]) & 0x1FF

def leaf(level, oa, ap, af, kind):
    if kind == "invalid": return 0
    t = 0b11 if level == 3 else 0b01
    if kind == "reserved": t = 0b01
    return (oa & 0xFFFF_FFFF_F000) | (af << 10) | (ap << 6) | (0xF << 2) | t

def map_one(level, ipa, word):
    table = VTTBR
    for l in range(level):
        a = table + idx(l, ipa) * 8
        d = mem.get(a, 0)
        if d & 1 and not d & 2: return False         # a block is already here
        if not d & 1:
            d = new_table() | 0b11; mem[a] = d
        table = d & 0xFFFF_FFFF_F000
    a = table + idx(level, ipa) * 8
    if a in mem: return False
    mem[a] = word
    return True

def walk(ipa, write):
    table = VTTBR
    for l in range(4):
        d = mem.get(table + idx(l, ipa) * 8, 0)
        if not d & 1: return fault(1, l)
        if l < 3 and d & 2: table = d & 0xFFFF_FFFF_F000; continue
        if l == 0 or (l == 3 and not d & 2): return fault(1, l)
        if not (d >> 10) & 1: return fault(2, l)
        if not (d >> (7 if write else 6)) & 1: return fault(3, l)
        sh = SHIFT[l]
        return ((d & 0xFFFF_FFFF_F000) >> sh << sh) | (ipa & ((1 << sh) - 1))

def fault(kind, l): return (1 << 63) | (kind << 60) | (l << 58)

maps = []
while len(maps) < N // 2:
    level = rng.choice([1, 2, 3, 3, 3, 2])
    sh = SHIFT[level]
    ipa = rng.randrange(0, 1 << 48) >> sh << sh
    oa = rng.randrange(0, 1 << 48) >> sh << sh
    kind = rng.choices(["ok", "invalid", "reserved"], [90, 6, 4])[0]
    if kind == "reserved" and level != 3: kind = "ok"
    af = 0 if rng.random() < 0.08 else 1
    ap = rng.choice([0b01, 0b10, 0b11, 0b11, 0b00])
    if map_one(level, ipa, leaf(level, oa, ap, af, kind)):
        maps.append((level, ipa))
os.makedirs("build", exist_ok=True)
with open("build/s2_mem.txt", "w") as f:
    for a in sorted(mem): f.write(f"{a:016x} {mem[a]:016x}\n")
with open("build/s2_vec.txt", "w") as f:
    probes = []
    for level, ipa in maps:
        probes.append(ipa | rng.randrange(0, 1 << SHIFT[level]))
    while len(probes) < N:
        probes.append(rng.randrange(0, 1 << 48))
    for ipa in probes:
        w = rng.random() < 0.5
        f.write(f"{VTTBR:012x} {ipa:012x} {int(w)} {walk(ipa, w):016x}\n")
kinds = {}
for line in open("build/s2_vec.txt"):
    e = int(line.split()[3], 16)
    k = "ok" if not e >> 63 else ["", "translation", "access flag", "permission"][(e >> 60) & 7]
    kinds[k] = kinds.get(k, 0) + 1
print(f"seed {SEED}: {N} probes, {len(mem)} table words, " + ", ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
