#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/oracle/serializer_unserializer_seed/src"
EXPECTED="$ROOT/test/oracle/serializer_unserializer_seed/expected.stdout"
OUT_DIR="${SERIALIZER_ORACLE_OUT_DIR:-$ROOT/.tmp/serializer-unserializer-oracle-seed}"
ACTUAL="$OUT_DIR/actual.stdout"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "serializer oracle seed: missing Haxe compiler '$HAXE_BIN'" >&2
  exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
  echo "serializer oracle seed: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$ACTUAL"

if ! diff -u "$EXPECTED" "$ACTUAL"; then
  echo "SERIALIZER_UNSERIALIZER_ORACLE_SEED:FAIL" >&2
  exit 1
fi

SERIALIZED_COUNT="$(grep -c '|serialized|' "$ACTUAL")"
DECODED_COUNT="$(grep -c '|decoded|' "$ACTUAL")"
ERROR_COUNT="$(grep -c '|error|' "$ACTUAL")"
cat >"$REPORT" <<EOF
{
  "contract": "serializer_unserializer_oracle_seed",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "source": "test/oracle/serializer_unserializer_seed/src/Main.hx",
  "expectedStdout": "test/oracle/serializer_unserializer_seed/expected.stdout",
  "actualStdout": ".tmp/serializer-unserializer-oracle-seed/actual.stdout",
  "caseCounts": {
    "serialized": $SERIALIZED_COUNT,
    "decoded": $DECODED_COUNT,
    "errors": $ERROR_COUNT
  },
  "cppResultPolicy": ["pass", "unsupported_diagnostic", "known_divergence"]
}
EOF

echo "SERIALIZER_UNSERIALIZER_ORACLE_SEED:PASS serialized=$SERIALIZED_COUNT decoded=$DECODED_COUNT errors=$ERROR_COUNT report=$REPORT"
