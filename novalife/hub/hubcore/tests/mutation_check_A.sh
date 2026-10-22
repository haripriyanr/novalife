#!/bin/sh
# Mutation check for module A tests: apply one deliberate bug to a COPY of the sources and
# require the matching test to FAIL.  Usage: tests/mutation_check_A.sh   (from anywhere)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
bad=0; total=0
# name | test | file | sed expression
while IFS='|' read -r name test file expr; do
  [ -z "$name" ] && continue
  rm -rf "$TMP/h"; mkdir -p "$TMP/h"
  cp -r "$ROOT/include" "$ROOT/src" "$ROOT/tests" "$TMP/h/"
  # tests read ../tools/... for the KATs
  ln -s "$ROOT/../tools" "$TMP/tools" 2>/dev/null
  sed -i "$expr" "$TMP/h/$file"
  if cmp -s "$TMP/h/$file" "$ROOT/$file"; then echo "MUTATION NOT APPLIED: $name"; bad=$((bad+1)); total=$((total+1)); continue; fi
  total=$((total+1))
  ( cd "$TMP/h" && CFLAGS_EXTRA="" sh tests/mybuild.sh "$test" >/dev/null 2>&1 && ./build/test_$test >/dev/null 2>&1 )
  if [ $? -eq 0 ]; then echo "SURVIVED  $name"; bad=$((bad+1)); else echo "caught    $name"; fi
done <<'LIST'
ascon rotation 19->20|ascon|src/ascon.c|s/ror(t0, 19)/ror(t0, 20)/
ascon IV bit|ascon|src/ascon.c|s/0x00001000808C0001ULL/0x00001000808C0003ULL/
ascon pad byte|ascon|src/ascon.c|s/(0x01ULL << (8u \* r))/(0x02ULL << (8u * r))/
ascon DSEP removed|ascon|src/ascon.c|s/s\[4\] ^= DSEP;/;/
ascon 8 rounds->7|ascon|src/ascon.c|s/permute(s, 8);\n            off += RATE;/X/;0,/permute(s, 8)/s//permute(s, 7)/
ascon mac domain|ascon|src/ascon.c|s/'v', '1'}/'v', '2'}/
ascon stream nonce|ascon|src/ascon.c|s/0x53, 0x54, 0x52, 0x4D/0x53, 0x54, 0x52, 0x4E/
tag len byte 11->10|tag_block|src/tag_block.c|s/msg\[HC_ASCON_MAC_DOMAIN_LEN\] = 11;/msg[HC_ASCON_MAC_DOMAIN_LEN] = 10;/
tag hub_id bytes swapped|tag_block|src/tag_block.c|s/(uint8_t)((hub_id >> 8) \& 0xFF);/(uint8_t)((hub_id >> 7) \& 0xFF);/
tag verify never ok|tag_block|src/tag_block.c|s/f->tag_ok = (f->expected_tag == f->tag);/f->tag_ok = 1;/
tag field offset|tag_block|src/tag_block.c|s/field(bits, 80, 128)/field(bits, 79, 127)/
tag build bit order|tag_block|src/tag_block.c|s/(7 - (i \& 7))) \& 1u/(i \& 7)) \& 1u/
polar frozen reorder (real bug found)|polar|src/polar.c|s/for (j = 1; !frozen_mask\[i\] \&\& j < nc; j++)/for (j = 1; j < nc; j++)/
polar unstable tie-break|polar|src/polar.c|s/cand\[q\].pm > t.pm/cand[q].pm >= t.pm/
polar F uses max|polar|src/polar.c|s/(aa < ab ? aa : ab)/(aa > ab ? aa : ab)/
polar G sign|polar|src/polar.c|s/u\[k\] ? b\[k\] - a\[k\] : b\[k\] + a\[k\]/u[k] ? b[k] + a[k] : b[k] - a[k]/
polar pm of bit 1 inverted|polar|src/polar.c|s/(leaf > 0.0 ? fabs(leaf) : 0.0)/(leaf < 0.0 ? fabs(leaf) : 0.0)/
polar last min pick|polar|src/polar.c|s/cur\[k\].pm < cur\[best\].pm/cur[k].pm <= cur[best].pm/
polar encode one stage short|polar|src/polar.c|s/step < N; step \*= 2)/step < N \/ 2; step *= 2)/
iwt floor shift -> truncating|iwt|src/iwt.c|s/return v >= 0 ? (int32_t)((uint32_t)v >> n) : ~(int32_t)((uint32_t)(~v) >> n);/return v \/ (1 << n);/
iwt update +2->+1|iwt|src/iwt.c|s/pd, d\[k\]), 2), 2)/pd, d[k]), 1), 2)/
iwt no right-edge replication|iwt|src/iwt.c|s/int32_t ne = (k + 1 < half) ? x\[(size_t)(2 \* k + 2) \* xs\] : e;/int32_t ne = (k + 1 < half) ? x[(size_t)(2 * k + 2) * xs] : 0;/
iwt inverse no clip|iwt|src/iwt.c|s/out\[i\] = out\[i\] < 0 ? 0 : (out\[i\] > 255 ? 255 : out\[i\]);/;/
iwt HL<->HH swap|iwt|src/iwt.c|s/HL\[(size_t)k \* w2 + c\] = cs\[k\];/HH[(size_t)k * w2 + c] = cs[k];/
LIST
echo "mutations: $total, not caught: $bad"
[ "$bad" -eq 0 ]
