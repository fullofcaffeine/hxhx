#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
FIXTURE_DIR="$ROOT/test/oracle/reflaxe_ocaml_exact_catch_control_seed"
SRC_DIR="$FIXTURE_DIR/src"
INVALID_DYNAMIC_FIRST_DIR="$FIXTURE_DIR/invalid_dynamic_first"
EXPECTED="$FIXTURE_DIR/expected.stdout"
OUT_DIR="${REFLAXE_OCAML_EXACT_CATCH_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-exact-catch-oracle}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "reflaxe.ocaml exact-catch oracle: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v node >/dev/null 2>&1; then
	echo "reflaxe.ocaml exact-catch oracle: missing Node.js" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "reflaxe.ocaml exact-catch oracle: missing Neko" >&2
	exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml exact-catch oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
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
		echo "REFLAXE_OCAML_EXACT_CATCH_ORACLE:FAIL route=$route" >&2
		exit 1
	fi
done

if "$HAXE_BIN" -cp "$INVALID_DYNAMIC_FIRST_DIR" -main Main --interp \
	>"$OUT_DIR/invalid-dynamic-first.stdout" 2>"$OUT_DIR/invalid-dynamic-first.stderr"; then
	echo "reflaxe.ocaml exact-catch oracle: Haxe accepted a catch after Dynamic" >&2
	exit 1
fi
if ! grep -q "This block is unreachable" "$OUT_DIR/invalid-dynamic-first.stderr" \
	|| ! grep -q "can be caught to Dynamic" "$OUT_DIR/invalid-dynamic-first.stderr"; then
	echo "reflaxe.ocaml exact-catch oracle: Haxe rejected catch-after-Dynamic without the expected diagnostic" >&2
	cat "$OUT_DIR/invalid-dynamic-first.stderr" >&2
	exit 1
fi

echo "REFLAXE_OCAML_EXACT_CATCH_ORACLE:PASS routes=3 cases=11"
