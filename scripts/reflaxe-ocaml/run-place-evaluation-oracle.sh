#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
FIXTURE_DIR="$ROOT/test/oracle/reflaxe_ocaml_place_evaluation_seed"
SRC_DIR="$FIXTURE_DIR/src"
EXPECTED="$FIXTURE_DIR/expected.stdout"
EXPECTED_NEKO="$FIXTURE_DIR/expected.neko.stdout"
OUT_DIR="${REFLAXE_OCAML_PLACE_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-place-evaluation-oracle}"
REPORT="$OUT_DIR/report.json"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "reflaxe.ocaml place oracle: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v node >/dev/null 2>&1; then
	echo "reflaxe.ocaml place oracle: missing Node.js" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "reflaxe.ocaml place oracle: missing Neko" >&2
	exit 127
fi
if [ ! -f "$EXPECTED" ] || [ ! -f "$EXPECTED_NEKO" ]; then
	echo "reflaxe.ocaml place oracle: missing expected output" >&2
	exit 2
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml place oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$OUT_DIR/interp.stdout"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main -js "$OUT_DIR/out.js"
node "$OUT_DIR/out.js" >"$OUT_DIR/js.stdout"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main -neko "$OUT_DIR/out.n"
neko "$OUT_DIR/out.n" >"$OUT_DIR/neko.stdout"

for route in interp js; do
	if ! diff -u "$EXPECTED" "$OUT_DIR/$route.stdout"; then
		echo "REFLAXE_OCAML_PLACE_EVALUATION_ORACLE:FAIL route=$route" >&2
		exit 1
	fi
done
if ! diff -u "$EXPECTED_NEKO" "$OUT_DIR/neko.stdout"; then
	echo "REFLAXE_OCAML_PLACE_EVALUATION_ORACLE:FAIL route=neko" >&2
	exit 1
fi

CASE_COUNT="$(wc -l <"$EXPECTED" | tr -d ' ')"
cat >"$REPORT" <<EOF
{
  "contract": "reflaxe_ocaml_place_evaluation_oracle",
  "oracle": "upstream-haxe-4.3.7",
  "haxeVersion": "$HAXE_VERSION",
  "routes": ["interp", "js-node", "neko"],
  "selectedOcamlOracle": "interp-js-source-order",
  "knownDivergence": "Neko evaluates the simple array-assignment index before its receiver; interpreter and JavaScript evaluate the receiver first. Compound assignment and updates agree.",
  "source": "test/oracle/reflaxe_ocaml_place_evaluation_seed/src/Main.hx",
  "expectedStdout": "test/oracle/reflaxe_ocaml_place_evaluation_seed/expected.stdout",
  "expectedNekoStdout": "test/oracle/reflaxe_ocaml_place_evaluation_seed/expected.neko.stdout",
  "caseCountPerRoute": $CASE_COUNT
}
EOF

echo "REFLAXE_OCAML_PLACE_EVALUATION_ORACLE:PASS routes=3 cases_per_route=$CASE_COUNT report=$REPORT"
