#!/usr/bin/env bash
# Runs the Sail checks: the eight TLBI scope assertions in spec/sail/checks.sail, and
# the Sail Stage 2 walk compiled to C against the Python walker for five seeds.
# Expects ./scripts/build_sim.sh to have been run.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0
echo "\$ sail --version"; sail --version
echo "\$ build/sail_checks"; build/sail_checks || fail=1
for seed in 1 2 3 4 5; do
  echo "\$ python3 tools/s2_vectors.py $seed 2000 && build/s2_ref"
  python3 tools/s2_vectors.py "$seed" 2000 && build/s2_ref || fail=1
done
python3 tools/s2_vectors.py 1 2000 >/dev/null
echo "exit status $fail"
exit $fail
