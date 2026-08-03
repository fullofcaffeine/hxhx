#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
FIXTURE_DIR="$ROOT/test/portable/fixtures/inheritance_override"
OUT_DIR="${REFLAXE_OCAML_INHERITANCE_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-inheritance-override-oracle}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "inheritance override oracle: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "inheritance override oracle: missing Neko" >&2
	exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "inheritance override oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 2
fi

mkdir -p "$OUT_DIR"
"$HAXE_BIN" -cp "$FIXTURE_DIR/src" -main Main --interp >"$OUT_DIR/interp.stdout"
"$HAXE_BIN" -cp "$FIXTURE_DIR/src" -main Main -neko "$OUT_DIR/out.n"
neko "$OUT_DIR/out.n" >"$OUT_DIR/neko.stdout"

for route in interp neko; do
	if ! diff -u "$FIXTURE_DIR/expected.stdout" "$OUT_DIR/$route.stdout"; then
		echo "INHERITANCE_OVERRIDE_ORACLE:FAIL route=$route" >&2
		exit 1
	fi
done

echo "INHERITANCE_OVERRIDE_ORACLE:PASS routes=2 cases=6"
