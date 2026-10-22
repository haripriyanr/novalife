#!/usr/bin/env bash
# Run a PL core's self-checking testbench with Icarus Verilog.
#
#   vivado/scripts/run_sim.sh <core_dir> [tb_file]
#
#   <core_dir>  directory under vivado/ip_repo/ (e.g. polar_encoder)
#   [tb_file]   testbench filename (default <core_dir>_tb.v)
#
# Generated conformance vectors in tools/tag_reference/vectors/ (*.mem, *.vh) are copied
# into a per-core build dir so `$readmemh` and `` `include `` resolve.  The build dir is
# regenerated on every run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VEC="$ROOT/tools/tag_reference/vectors"

CORE="${1:?usage: run_sim.sh <core_dir> [tb_file]}"
TB="${2:-${CORE}_tb.v}"
SRC="$ROOT/vivado/ip_repo/$CORE"
BUILD="$ROOT/vivado/sim_build/$CORE"

[ -d "$SRC" ] || { echo "no such core dir: $SRC" >&2; exit 2; }
[ -f "$SRC/$TB" ] || { echo "no such testbench: $SRC/$TB" >&2; exit 2; }

rm -rf "$BUILD"
mkdir -p "$BUILD"
cp -f "$VEC"/*.mem "$VEC"/*.vh "$BUILD"/ 2>/dev/null || true
cp -f "$SRC"/*.vh "$BUILD"/ 2>/dev/null || true

# sources: every .v in the core dir except testbenches, plus the chosen testbench
mapfile -t SOURCES < <(find "$SRC" -maxdepth 1 -name '*.v' ! -name '*_tb.v' | sort)
# optional deps.txt: other core dirs (one per line) whose non-tb sources this core instantiates
if [ -f "$SRC/deps.txt" ]; then
  while read -r dep; do
    [ -n "$dep" ] || continue
    mapfile -t -O "${#SOURCES[@]}" SOURCES < <(find "$ROOT/vivado/ip_repo/$dep" -maxdepth 1 -name '*.v' ! -name '*_tb.v' | sort)
  done < "$SRC/deps.txt"
fi
SOURCES+=("$SRC/$TB")

cd "$BUILD"
echo "== sim $CORE ($TB) =="
iverilog -g2012 -Wall -o "$BUILD/tb.vvp" -I"$BUILD" "${SOURCES[@]}"
vvp "$BUILD/tb.vvp"
