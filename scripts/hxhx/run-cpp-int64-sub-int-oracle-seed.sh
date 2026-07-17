#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/oracle/cpp_int64_sub_int_seed/src"
EXPECTED="$ROOT/test/oracle/cpp_int64_sub_int_seed/expected.stdout"
OUT_DIR="${CPP_INT64_SUB_INT_ORACLE_OUT_DIR:-$ROOT/.tmp/cpp-int64-sub-int-oracle-seed}"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "cpp Int64 subInt oracle seed: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v node >/dev/null 2>&1; then
	echo "cpp Int64 subInt oracle seed: missing Node.js" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "cpp Int64 subInt oracle seed: missing Neko" >&2
	exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "cpp Int64 subInt oracle seed: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$OUT_DIR/interp.stdout"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main -js "$OUT_DIR/out.js"
node "$OUT_DIR/out.js" >"$OUT_DIR/js.stdout"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main -neko "$OUT_DIR/out.n"
neko "$OUT_DIR/out.n" >"$OUT_DIR/neko.stdout"

for route in interp js neko; do
	if ! diff -u "$EXPECTED" "$OUT_DIR/$route.stdout"; then
		echo "CPP_INT64_SUB_INT_ORACLE_SEED:FAIL route=$route" >&2
		exit 1
	fi
done

CASE_COUNT="$(wc -l <"$EXPECTED" | tr -d ' ')"
cat >"$REPORT" <<EOF
{
  "contract": "cpp_int64_sub_int_oracle_seed",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "routes": ["interp", "js-node", "neko"],
  "source": "test/oracle/cpp_int64_sub_int_seed/src/Main.hx",
  "expectedStdout": "test/oracle/cpp_int64_sub_int_seed/expected.stdout",
  "caseCountPerRoute": $CASE_COUNT
}
EOF

echo "CPP_INT64_SUB_INT_ORACLE_SEED:PASS routes=3 cases_per_route=$CASE_COUNT report=$REPORT"
