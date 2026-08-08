#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
FIXTURE_DIR="$ROOT/test/oracle/reflaxe_ocaml_reflect_compare_seed"
SRC_DIR="$FIXTURE_DIR/src"
EXPECTED_INTERP_JS="$FIXTURE_DIR/expected.interp-js.stdout"
EXPECTED_NEKO="$FIXTURE_DIR/expected.neko.stdout"
OUT_DIR="${REFLAXE_OCAML_REFLECT_COMPARE_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-reflect-compare-oracle}"

for command in "$HAXE_BIN" node neko; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "reflaxe.ocaml Reflect.compare oracle: missing command '$command'" >&2
		exit 127
	fi
done

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml Reflect.compare oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main --interp >"$OUT_DIR/interp.stdout"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main -js "$OUT_DIR/out.js"
node "$OUT_DIR/out.js" >"$OUT_DIR/js.stdout"
"$HAXE_BIN" -cp "$SRC_DIR" -main Main -neko "$OUT_DIR/out.n"
neko "$OUT_DIR/out.n" >"$OUT_DIR/neko.stdout"

diff -u "$EXPECTED_INTERP_JS" "$OUT_DIR/interp.stdout"
diff -u "$EXPECTED_INTERP_JS" "$OUT_DIR/js.stdout"
diff -u "$EXPECTED_NEKO" "$OUT_DIR/neko.stdout"

echo "REFLAXE_OCAML_REFLECT_COMPARE_ORACLE:PASS routes=3 stable_cases=15 target_variant_cases=4"
