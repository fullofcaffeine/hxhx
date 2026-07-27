#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SEED="$ROOT/test/oracle/reflaxe_ocaml_function_value_signature_matrix_seed"
OUT_DIR="${REFLAXE_OCAML_FUNCTION_VALUE_SIGNATURE_MATRIX_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-function-value-signature-matrix-oracle}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "reflaxe.ocaml function-value signature-matrix oracle: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v node >/dev/null 2>&1; then
	echo "reflaxe.ocaml function-value signature-matrix oracle: missing Node.js" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "reflaxe.ocaml function-value signature-matrix oracle: missing Neko" >&2
	exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml function-value signature-matrix oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 2
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

run_route() {
	local route="$1"
	local actual="$OUT_DIR/$route.stdout"
	case "$route" in
		interp)
			"$HAXE_BIN" -cp "$SEED/src" -main Main --interp >"$actual"
			;;
		js)
			"$HAXE_BIN" -cp "$SEED/src" -main Main -js "$OUT_DIR/oracle.js"
			node "$OUT_DIR/oracle.js" >"$actual"
			;;
		neko)
			"$HAXE_BIN" -cp "$SEED/src" -main Main -neko "$OUT_DIR/oracle.n"
			neko "$OUT_DIR/oracle.n" >"$actual"
			;;
		*)
			echo "Unknown oracle route: $route" >&2
			exit 1
			;;
	esac
	if ! diff -u "$SEED/expected.stdout" "$actual"; then
		echo "REFLAXE_OCAML_FUNCTION_VALUE_SIGNATURE_MATRIX_ORACLE:FAIL route=$route" >&2
		exit 1
	fi
}

for route in interp js neko; do
	run_route "$route"
done

echo "REFLAXE_OCAML_FUNCTION_VALUE_SIGNATURE_MATRIX_ORACLE:PASS routes=3 cases=11"
