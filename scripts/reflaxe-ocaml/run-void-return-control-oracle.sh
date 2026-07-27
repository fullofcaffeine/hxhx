#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
FIXTURE_DIR="$ROOT/test/oracle/reflaxe_ocaml_void_return_control_seed"
SRC_DIR="$FIXTURE_DIR/src"
EXPECTED="$FIXTURE_DIR/expected.stdout"
OUT_DIR="${REFLAXE_OCAML_VOID_RETURN_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-void-return-oracle}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "reflaxe.ocaml Void-return control oracle: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v node >/dev/null 2>&1; then
	echo "reflaxe.ocaml Void-return control oracle: missing Node.js" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "reflaxe.ocaml Void-return control oracle: missing Neko" >&2
	exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml Void-return control oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
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
		echo "REFLAXE_OCAML_VOID_RETURN_CONTROL_ORACLE:FAIL route=$route" >&2
		exit 1
	fi
done

echo "REFLAXE_OCAML_VOID_RETURN_CONTROL_ORACLE:PASS routes=3 cases=8"
