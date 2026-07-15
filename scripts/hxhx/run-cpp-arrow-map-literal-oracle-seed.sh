#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/oracle/cpp_arrow_map_literal_seed/src"
EXPECTED="$ROOT/test/oracle/cpp_arrow_map_literal_seed/expected.stdout"
OUT_DIR="${CPP_ARROW_MAP_LITERAL_ORACLE_OUT_DIR:-$ROOT/.tmp/cpp-arrow-map-literal-oracle-seed}"
ACTUAL="$OUT_DIR/actual.stdout"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "cpp arrow map literal oracle seed: missing Haxe compiler '$HAXE_BIN'" >&2
  exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
  echo "cpp arrow map literal oracle seed: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$ACTUAL"

if ! diff -u "$EXPECTED" "$ACTUAL"; then
  echo "CPP_ARROW_MAP_LITERAL_ORACLE_SEED:FAIL" >&2
  exit 1
fi

CASE_COUNT="$(wc -l <"$ACTUAL" | tr -d ' ')"

cat >"$REPORT" <<EOF
{
  "contract": "cpp_arrow_map_literal_oracle_seed",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "source": "test/oracle/cpp_arrow_map_literal_seed/src/Main.hx",
  "expectedStdout": "test/oracle/cpp_arrow_map_literal_seed/expected.stdout",
  "actualStdout": ".tmp/cpp-arrow-map-literal-oracle-seed/actual.stdout",
  "caseCount": $CASE_COUNT
}
EOF

echo "CPP_ARROW_MAP_LITERAL_ORACLE_SEED:PASS cases=$CASE_COUNT report=$REPORT"
