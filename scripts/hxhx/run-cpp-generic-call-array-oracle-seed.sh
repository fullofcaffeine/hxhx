#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/oracle/cpp_generic_call_array_seed/src"
EXPECTED="$ROOT/test/oracle/cpp_generic_call_array_seed/expected.stdout"
OUT_DIR="${CPP_GENERIC_CALL_ARRAY_ORACLE_OUT_DIR:-$ROOT/.tmp/cpp-generic-call-array-oracle-seed}"
ACTUAL="$OUT_DIR/actual.stdout"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "cpp generic call array oracle seed: missing Haxe compiler '$HAXE_BIN'" >&2
  exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
  echo "cpp generic call array oracle seed: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$ACTUAL"

if ! diff -u "$EXPECTED" "$ACTUAL"; then
  echo "CPP_GENERIC_CALL_ARRAY_ORACLE_SEED:FAIL" >&2
  exit 1
fi

GENERIC_COUNT="$(grep -c '^generic-call-array-01:\(flat\|nested\|concrete\)|' "$ACTUAL")"
CONTROL_COUNT="$(grep -c '^generic-call-array-01:control|' "$ACTUAL")"

cat >"$REPORT" <<EOF
{
  "contract": "cpp_generic_call_array_oracle_seed",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "source": "test/oracle/cpp_generic_call_array_seed/src/Main.hx",
  "expectedStdout": "test/oracle/cpp_generic_call_array_seed/expected.stdout",
  "actualStdout": ".tmp/cpp-generic-call-array-oracle-seed/actual.stdout",
  "caseCounts": {
    "generic": $GENERIC_COUNT,
    "nonGenericControl": $CONTROL_COUNT
  },
  "cppResultPolicy": ["pass", "unsupported_diagnostic", "known_divergence"]
}
EOF

echo "CPP_GENERIC_CALL_ARRAY_ORACLE_SEED:PASS generic=$GENERIC_COUNT nonGenericControl=$CONTROL_COUNT report=$REPORT"
