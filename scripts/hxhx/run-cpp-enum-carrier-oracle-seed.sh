#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/oracle/cpp_enum_carrier_seed/src"
EXPECTED="$ROOT/test/oracle/cpp_enum_carrier_seed/expected.stdout"
OUT_DIR="${CPP_ENUM_CARRIER_ORACLE_OUT_DIR:-$ROOT/.tmp/cpp-enum-carrier-oracle-seed}"
ACTUAL="$OUT_DIR/actual.stdout"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "cpp enum carrier oracle seed: missing Haxe compiler '$HAXE_BIN'" >&2
  exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
  echo "cpp enum carrier oracle seed: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$ACTUAL"

if ! diff -u "$EXPECTED" "$ACTUAL"; then
  echo "CPP_ENUM_CARRIER_ORACLE_SEED:FAIL" >&2
  exit 1
fi

ZERO_COUNT="$(grep -c '^enum-zero-01|' "$ACTUAL")"
PAYLOAD_COUNT="$(grep -c '^enum-payload-01|' "$ACTUAL")"
MAP_KEY_COUNT="$(grep -c '^enum-map-key-01|' "$ACTUAL")"
GENERIC_ID_COUNT="$(grep -c '^enum-generic-id-01:' "$ACTUAL")"
EQ_COUNT="$(grep -c '^enum-eq-01:' "$ACTUAL")"
SWITCH_COUNT="$(grep -c '^enum-switch-01|' "$ACTUAL")"
TYPE_COUNT="$(grep -c '^enum-type-create-01:' "$ACTUAL")"
REFLECT_COUNT="$(grep -c '^enum-reflect-01|' "$ACTUAL")"
DYNAMIC_COUNT="$(grep -c '^enum-dynamic-01|' "$ACTUAL")"
SERIALIZER_COUNT="$(grep -c '^enum-serializer-01:' "$ACTUAL")"

cat >"$REPORT" <<EOF
{
  "contract": "cpp_enum_carrier_oracle_seed",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "source": "test/oracle/cpp_enum_carrier_seed/src/Main.hx",
  "expectedStdout": "test/oracle/cpp_enum_carrier_seed/expected.stdout",
  "actualStdout": ".tmp/cpp-enum-carrier-oracle-seed/actual.stdout",
  "caseCounts": {
    "zero": $ZERO_COUNT,
    "payload": $PAYLOAD_COUNT,
    "mapKey": $MAP_KEY_COUNT,
    "genericIdentity": $GENERIC_ID_COUNT,
    "enumEq": $EQ_COUNT,
    "switch": $SWITCH_COUNT,
    "typeFactory": $TYPE_COUNT,
    "reflection": $REFLECT_COUNT,
    "dynamic": $DYNAMIC_COUNT,
    "serializer": $SERIALIZER_COUNT
  },
  "cppResultPolicy": ["pass", "unsupported_diagnostic", "known_divergence"]
}
EOF

echo "CPP_ENUM_CARRIER_ORACLE_SEED:PASS zero=$ZERO_COUNT payload=$PAYLOAD_COUNT mapKey=$MAP_KEY_COUNT genericIdentity=$GENERIC_ID_COUNT enumEq=$EQ_COUNT switch=$SWITCH_COUNT typeFactory=$TYPE_COUNT reflection=$REFLECT_COUNT dynamic=$DYNAMIC_COUNT serializer=$SERIALIZER_COUNT report=$REPORT"
