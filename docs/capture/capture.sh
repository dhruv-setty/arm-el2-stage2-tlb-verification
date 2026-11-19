#!/usr/bin/env bash
# Produces the README figures on a real X display (Xvfb). Schematics come from Yosys
# and netlistsvg; every other figure is a screenshot of the named tool running the
# sources in this repository. No figure is drawn by hand. Logs of every run are kept
# next to the images in docs/screenshots/.
set -euo pipefail
cd "$(dirname "$0")/../.."
export OUT="$PWD/build/capture"; shots=docs/screenshots; mkdir -p "$OUT" "$shots"
TLA_JAR="${TLA_JAR:-tools/tla2tools.jar}"
if [ ! -f "$TLA_JAR" ]; then
  mkdir -p tools
  curl -sSL -o "$TLA_JAR" https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
fi
export TLA_JAR="$(cd "$(dirname "$TLA_JAR")" && pwd)/$(basename "$TLA_JAR")"

# 1. Schematics straight from the RTL (Yosys proc, opt -full, clean; no technology mapping).
schem() { # name top src width(0 = SVG only) [chparam]
  local name=$1 top=$2 src=$3 w=$4 cp=${5:-}
  yosys -q -p "read_verilog -sv $src; ${cp:+chparam -set $cp $top;} hierarchy -top $top; proc; opt -full; clean; write_json $OUT/$name.json; tee -q -o $OUT/$name.stat stat"
  netlistsvg "$OUT/$name.json" -o "$shots/schematic_$name.svg"
  if [ "$w" != 0 ]; then rsvg-convert -b white -w "$w" "$shots/schematic_$name.svg" -o "$shots/schematic_$name.png"; fi
}
schem s2_walker s2_walker rtl/s2_walker.sv 3200
schem s2_tlb_n2 s2_tlb rtl/s2_tlb.sv 3200 "N 2"
schem s2_tlb s2_tlb rtl/s2_tlb.sv 0
cat "$OUT"/s2_walker.stat "$OUT"/s2_tlb_n2.stat "$OUT"/s2_tlb.stat > "$shots/schematic_stat.log"

# 2. Build the Sail reference and the Verilator harness, then the traced capture harness.
./scripts/build_sim.sh > "$OUT/build.log" 2>&1
rm -rf build/obj_wv
verilator -Wall -Wno-UNUSEDSIGNAL --trace --timescale-override 1ns/1ns --cc --exe --build -O2 --Mdir build/obj_wv \
  "$PWD/rtl/s2_walker.sv" "$PWD/docs/capture/tb_s2_walker_vcd.cpp" -o tb_s2_walker_vcd > "$OUT/build_wv.log" 2>&1

# 3. Simulations (also writing the TLB VCD), then the traced walker runs.
docs/capture/run_tbs.sh > "$OUT/sim.log" 2>&1 || echo "run_tbs.sh returned non zero" >> "$OUT/sim.log"
python3 tools/s2_vectors.py 1 2000 > /dev/null
{ build/obj_wv/tb_s2_walker_vcd 1 "$OUT/s2_walker_lat1.vcd" 120
  build/obj_wv/tb_s2_walker_vcd 8 "$OUT/s2_walker_lat8.vcd" 120; } >> "$OUT/sim.log" 2>&1 || echo "traced walker returned non zero" >> "$OUT/sim.log"

# 4. Screenshots on a virtual display.
export DISPLAY=:99
Xvfb :99 -screen 0 1600x1200x24 -nolisten tcp & sleep 2
openbox & sleep 1
XT=(-fa 'DejaVu Sans Mono' -fs 10 -bg '#1e1e1e' -fg '#d4d4d4')

# 4a. Testbenches open in Geany above an xterm that runs them.
cfg=$(mktemp -d)
printf '[geany]\npref_main_load_session=false\nmsgwindow_visible=false\nsidebar_visible=true\npref_toolbar_show=true\n' > "$cfg/geany.conf"
geany -c "$cfg" sim/tb_s2_walker.cpp rtl/tb/tb_s2_tlb.sv >/dev/null 2>&1 &
gw=$(xdotool search --sync --onlyvisible --class Geany | head -1)
xdotool windowmove "$gw" 0 0 windowsize "$gw" 1600 700; sleep 2
xterm -geometry 200x26+0+700 "${XT[@]}" -T 'run_tbs.sh: Icarus Verilog and Verilator' \
  -e bash -c 'docs/capture/run_tbs.sh 2>&1 | tee build/capture/sim_term.log; exec sleep 600' &
tbx=$!
for _ in $(seq 1 60); do grep -q "^exit status" "$OUT/sim_term.log" 2>/dev/null && break; sleep 2; done; sleep 2
i=1
for tb in rtl/tb/tb_s2_tlb.sv sim/tb_s2_walker.cpp; do
  geany -c "$cfg" "$tb" >/dev/null 2>&1; sleep 2
  xdotool windowactivate --sync "$gw"; sleep 1
  import -window root "$shots/testbench_$i-$(basename "${tb%.*}").png"
  i=$((i+1))
done
kill $tbx || true; pkill -f geany || true; sleep 1

# 4b. GTKWave views of the VCDs.
wave() { # name vcd height signals...
  local name=$1 vcd=$2 h=$3; shift 3
  { echo "gtkwave::addSignalsFromList [list $*]"; echo "gtkwave::/Time/Zoom/Zoom_Best_Fit"; } > "$OUT/$name.tcl"
  gtkwave --rcvar "initial_window_x 1600" --rcvar "initial_window_y $h" "$vcd" -S "$OUT/$name.tcl" >/dev/null 2>&1 &
  local pid=$! ww
  ww=$(xdotool search --sync --onlyvisible --class gtkwave | tail -1)
  xdotool windowmove "$ww" 0 0; sleep 4
  xdotool windowactivate --sync "$ww"; sleep 1
  import -window "$ww" "$shots/waveform_$name.png"
  kill $pid; sleep 2
}
T=tb_s2_tlb
wave tb_s2_tlb "$OUT/tb_s2_tlb.vcd" 760 $T.clk $T.rst_n $T.fill $T.fill_combined $T.fill_global $T.fill_vmid $T.fill_asid $T.fill_page \
  $T.dut.rr $T.dut.v $T.tlbi $T.tlbi_op $T.tlbi_vmid $T.tlbi_asid $T.dut.kill $T.lk_combined $T.lk_vmid $T.lk_asid $T.lk_page $T.lk_hit $T.lk_pa $T.errors
W=TOP.s2_walker
for lat in 1 8; do
  wave s2_walker_lat$lat "$OUT/s2_walker_lat$lat.vcd" 700 $W.clk $W.rst_n $W.req_valid $W.req_ready $W.ipa $W.write $W.state $W.level \
    $W.mem_req $W.mem_addr $W.mem_rvalid $W.mem_rdata $W.resp_valid $W.resp
done

# 4c. Terminals: TLC, Sail, lint and synthesis.
term() { # name rows done-pattern command
  local name=$1 rows=$2 pat=$3 cmd=$4 pid wid
  xterm -geometry "170x$rows+0+0" "${XT[@]}" -T "$name" -e bash -c "$cmd 2>&1 | tee build/capture/$name.log; exec sleep 600" &
  pid=$!
  for _ in $(seq 1 150); do grep -q "$pat" "$OUT/$name.log" 2>/dev/null && break; sleep 2; done; sleep 3
  wid=$(xdotool search --sync --name "^$name\$" | head -1)
  xdotool windowactivate --sync "$wid"; sleep 1
  import -window "$wid" "$shots/terminal_$name.png"
  cp "$OUT/$name.log" "$shots/terminal_$name.log"
  kill $pid || true; sleep 1
}
term tlc_S2Unmap               30 "TLC run of" "docs/capture/tlc_run.sh S2Unmap"
term tlc_S2Unmap_no_vmalle1    62 "TLC run of" "docs/capture/tlc_run.sh S2Unmap_no_vmalle1"
term tlc_S2Unmap_vmalle1_first 76 "TLC run of" "docs/capture/tlc_run.sh S2Unmap_vmalle1_first"
term sail                      30 "^exit status" "docs/capture/sail_run.sh"
term lint_synth                30 "^s2_tlb," "docs/capture/lint_synth.sh"

cp "$OUT/sim.log" "$shots/sim.log"
cat "$OUT/sim.log"
ls -la "$shots"
