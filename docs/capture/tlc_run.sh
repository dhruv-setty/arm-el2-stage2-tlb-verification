#!/usr/bin/env bash
# Runs TLC on one configuration of spec/tla/S2Unmap.tla with -difftrace, so that each
# counterexample state lists only the variables that changed. Parser progress lines
# are filtered out; every other line is TLC output as printed.
set -uo pipefail
cd "$(dirname "$0")/../../spec/tla"
jar=${TLA_JAR:-../../tools/tla2tools.jar}
echo "\$ java -cp tla2tools.jar tlc2.TLC -workers 1 -difftrace -config $1.cfg S2Unmap.tla"
java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers 1 -cleanup -difftrace -config "$1.cfg" S2Unmap.tla 2>&1 \
  | grep -v -e '^Parsing file' -e '^Semantic processing' -e '^Linting of' -e '^Trace exploration spec path'
rm -rf states ./*_TTrace_* 2>/dev/null
echo "(TLC run of $1.cfg finished)"
