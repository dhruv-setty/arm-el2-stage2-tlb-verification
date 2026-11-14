#!/usr/bin/env bash
# Stage 2 walker cross check and latency sweep: five seeds of 2,000 probes,
# each checked against the Sail model, then the RTL at three memory latencies.
set -euo pipefail
cd "$(dirname "$0")/.."
out=bench/results; mkdir -p "$out" build
./scripts/build_sim.sh >/dev/null
printf "seed,probes,ok,translation,access_flag,permission,sail_mismatches,latency,rtl_mismatches,cycles_per_walk,reads_per_walk,four_level_walks,four_level_cycles\n" > "$out/s2_walker.csv"
for seed in 1 2 3 4 5; do
  g=$(python3 tools/s2_vectors.py "$seed" 2000)
  ok=$(grep -oE "ok [0-9]+" <<<"$g" | cut -d' ' -f2); tr=$(grep -oE "translation [0-9]+" <<<"$g" | cut -d' ' -f2)
  af=$(grep -oE "access flag [0-9]+" <<<"$g" | cut -d' ' -f3); pm=$(grep -oE "permission [0-9]+" <<<"$g" | cut -d' ' -f2)
  s=$(build/s2_ref); sm=$(grep -oE "[0-9]+ mismatches" <<<"$s" | cut -d' ' -f1)
  for lat in 1 8 32; do
    r=$(build/obj_w/tb_s2_walker "$lat")
    rm_=$(grep -oE "[0-9]+ mismatches" <<<"$r" | cut -d' ' -f1)
    cpw=$(grep -oE "[0-9.]+ cycles and" <<<"$r" | cut -d' ' -f1)
    rpw=$(grep -oE "[0-9.]+ table reads" <<<"$r" | cut -d' ' -f1)
    fl=$(grep -oE "[0-9]+ four level walks at [0-9.]+" <<<"$r")
    echo "$seed,2000,$ok,$tr,$af,$pm,$sm,$lat,$rm_,$cpw,$rpw,$(cut -d' ' -f1 <<<"$fl"),$(awk '{print $NF}' <<<"$fl")" >> "$out/s2_walker.csv"
  done
done
python3 tools/s2_vectors.py 1 400 >/dev/null
cat "$out/s2_walker.csv"
