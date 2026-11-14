// Drives rtl/s2_walker.sv with build/s2_vec.txt over the tables in
// build/s2_mem.txt and checks every result against the expected word, which
// sim/s2_ref.c has already checked against the Sail model.
// Usage: tb_s2_walker [memory latency in cycles]
#include "Vs2_walker.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <unordered_map>

int main(int argc, char **argv) {
  int lat = argc > 1 ? atoi(argv[1]) : 1;
  std::unordered_map<uint64_t, uint64_t> mem;
  FILE *m = fopen("build/s2_mem.txt", "r"), *v = fopen("build/s2_vec.txt", "r");
  if (!m || !v) { fprintf(stderr, "run tools/s2_vectors.py first\n"); return 2; }
  unsigned long long a, d;
  while (fscanf(m, "%llx %llx", &a, &d) == 2) mem[a] = d;

  Verilated::commandArgs(argc, argv);
  Vs2_walker t;
  auto tick = [&] { t.clk = 0; t.eval(); t.clk = 1; t.eval(); };
  t.rst_n = 0; t.req_valid = 0; t.mem_rvalid = 0; tick(); t.rst_n = 1; tick();

  unsigned long long vt, ipa, exp; int w;
  long n = 0, bad = 0, cycles = 0, reads = 0, full = 0, full_cycles = 0;
  while (fscanf(v, "%llx %llx %d %llx", &vt, &ipa, &w, &exp) == 4) {
    t.vttbr = vt; t.ipa = ipa; t.write = w; t.req_valid = 1;
    tick(); t.req_valid = 0;
    long c = 1; int countdown = -1; uint64_t addr = 0; long r0 = reads;
    while (!t.resp_valid && c < 10000) {
      t.mem_rvalid = 0;
      if (countdown == 0) { t.mem_rvalid = 1; t.mem_rdata = mem.count(addr) ? mem[addr] : 0; countdown = -1; }
      else if (countdown > 0) countdown--;
      if (t.mem_req) { addr = t.mem_addr; countdown = lat - 1; reads++; }
      tick(); c++;
    }
    t.mem_rvalid = 0;
    cycles += c;
    if (reads - r0 == 4) { full++; full_cycles += c; }
    if (t.resp != exp) { if (bad < 5) printf("mismatch ipa %012llx w %d rtl %016llx expect %016llx\n", ipa, w, (unsigned long long)t.resp, exp); bad++; }
    n++;
  }
  printf("%s rtl stage 2 walker: %ld probes, %ld mismatches, latency %d, %.2f cycles and %.2f table reads per walk, %ld four level walks at %.2f cycles\n",
         bad ? "FAIL" : "PASS", n, bad, lat, (double)cycles / n, (double)reads / n, full, full ? (double)full_cycles / full : 0.0);
  return bad != 0;
}
