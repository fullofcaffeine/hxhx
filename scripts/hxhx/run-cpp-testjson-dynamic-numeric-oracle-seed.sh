#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/oracle/cpp_testjson_dynamic_numeric_seed/src"
EXPECTED="$ROOT/test/oracle/cpp_testjson_dynamic_numeric_seed/expected.stdout"
OUT_DIR="${CPP_TESTJSON_ORACLE_OUT_DIR:-$ROOT/.tmp/cpp-testjson-dynamic-numeric-oracle-seed}"
ACTUAL="$OUT_DIR/actual.stdout"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "cpp TestJson oracle seed: missing Haxe compiler '$HAXE_BIN'" >&2
  exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
  echo "cpp TestJson oracle seed: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$ACTUAL"

if ! diff -u "$EXPECTED" "$ACTUAL"; then
  echo "CPP_TESTJSON_DYNAMIC_NUMERIC_ORACLE_SEED:FAIL" >&2
  exit 1
fi

count_lines() {
  grep -c "$1" "$ACTUAL" || true
}

JSON_COUNT="$(count_lines '|json|')"
PRINTER_COUNT="$(count_lines '|printer|')"
ROUND_COUNT="$(count_lines '|round|')"
POS_COUNT="$(count_lines '|pos|')"
ERROR_COUNT="$(count_lines '|error|')"
cat >"$REPORT" <<EOF
{
  "contract": "cpp_testjson_dynamic_numeric_oracle_seed",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "source": "test/oracle/cpp_testjson_dynamic_numeric_seed/src/Main.hx",
  "expectedStdout": "test/oracle/cpp_testjson_dynamic_numeric_seed/expected.stdout",
  "actualStdout": ".tmp/cpp-testjson-dynamic-numeric-oracle-seed/actual.stdout",
  "caseCounts": {
    "json": $JSON_COUNT,
    "printer": $PRINTER_COUNT,
    "round": $ROUND_COUNT,
    "posInfos": $POS_COUNT,
    "errors": $ERROR_COUNT
  },
  "cppResultPolicy": ["pass", "unsupported_diagnostic", "known_divergence"]
}
EOF

echo "CPP_TESTJSON_DYNAMIC_NUMERIC_ORACLE_SEED:PASS json=$JSON_COUNT printer=$PRINTER_COUNT round=$ROUND_COUNT posInfos=$POS_COUNT errors=$ERROR_COUNT report=$REPORT"
