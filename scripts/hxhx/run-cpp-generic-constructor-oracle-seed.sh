#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/oracle/cpp_generic_constructor_seed/src"
EXPECTED="$ROOT/test/oracle/cpp_generic_constructor_seed/expected.stdout"
OUT_DIR="${CPP_GENERIC_CONSTRUCTOR_ORACLE_OUT_DIR:-$ROOT/.tmp/cpp-generic-constructor-oracle-seed}"
ACTUAL="$OUT_DIR/actual.stdout"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "cpp generic constructor oracle seed: missing Haxe compiler '$HAXE_BIN'" >&2
  exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
  echo "cpp generic constructor oracle seed: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$ACTUAL"

if ! diff -u "$EXPECTED" "$ACTUAL"; then
  echo "CPP_GENERIC_CONSTRUCTOR_ORACLE_SEED:FAIL" >&2
  exit 1
fi

ZERO_COUNT="$(grep -c '^generic-ctor-01:zero-' "$ACTUAL")"
PARAM_COUNT="$(grep -c '^generic-ctor-01:param-' "$ACTUAL")"
PLAIN_COUNT="$(grep -c '^generic-ctor-01:plain-' "$ACTUAL")"

cat >"$REPORT" <<EOF
{
  "contract": "cpp_generic_constructor_oracle_seed",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "source": "test/oracle/cpp_generic_constructor_seed/src/Main.hx",
  "expectedStdout": "test/oracle/cpp_generic_constructor_seed/expected.stdout",
  "actualStdout": ".tmp/cpp-generic-constructor-oracle-seed/actual.stdout",
  "caseCounts": {
    "zeroArgGeneric": $ZERO_COUNT,
    "parameterizedGeneric": $PARAM_COUNT,
    "plainZeroArg": $PLAIN_COUNT
  },
  "cppResultPolicy": ["pass", "unsupported_diagnostic", "known_divergence"]
}
EOF

echo "CPP_GENERIC_CONSTRUCTOR_ORACLE_SEED:PASS zeroArgGeneric=$ZERO_COUNT parameterizedGeneric=$PARAM_COUNT plainZeroArg=$PLAIN_COUNT report=$REPORT"
