/* Runs the Sail Stage 2 walk (compiled to C) over build/s2_vec.txt and
   compares every result with the expected word. */
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

#define MAXW 65536
static uint64_t pa_[MAXW], dw_[MAXW];
static int nw;

uint64_t read_pt(uint64_t a) {
  for (int i = 0; i < nw; i++) if (pa_[i] == a) return dw_[i];
  return 0;
}

extern void model_init(void);
extern void model_fini(void);
extern uint64_t zs2_translate(uint64_t vttbr, uint64_t ipa, bool write);

int main(void) {
  FILE *m = fopen("build/s2_mem.txt", "r"), *v = fopen("build/s2_vec.txt", "r");
  if (!m || !v) { fprintf(stderr, "run tools/s2_vectors.py first\n"); return 2; }
  unsigned long long a, d, t, ipa, exp; int w;
  while (nw < MAXW && fscanf(m, "%llx %llx", &a, &d) == 2) { pa_[nw] = a; dw_[nw] = d; nw++; }
  model_init();
  int n = 0, bad = 0;
  while (fscanf(v, "%llx %llx %d %llx", &t, &ipa, &w, &exp) == 4) {
    uint64_t got = zs2_translate(t, ipa, w);
    if (got != exp) { if (bad < 5) printf("mismatch ipa %012llx w %d sail %016llx expect %016llx\n", ipa, w, (unsigned long long)got, exp); bad++; }
    n++;
  }
  model_fini();
  printf("%s sail stage 2: %d probes, %d mismatches\n", bad ? "FAIL" : "PASS", n, bad);
  return bad != 0;
}
