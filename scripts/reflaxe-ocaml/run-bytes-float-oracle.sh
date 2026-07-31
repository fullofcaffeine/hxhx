#!/usr/bin/env bash
set -euo pipefail

# Records the shared observable Float32/Float64 Bytes behavior of Haxe 4.3.7
# Eval and Neko. The seed intentionally checks NaN classification without
# treating either target's exact NaN payload as a universal Haxe contract.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SEED="$ROOT/test/oracle/reflaxe_ocaml_bytes_float_seed"
OUT_DIR="${REFLAXE_OCAML_BYTES_FLOAT_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-bytes-float-oracle}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "reflaxe.ocaml Bytes Float oracle: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "reflaxe.ocaml Bytes Float oracle: missing Neko" >&2
	exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml Bytes Float oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 2
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"$HAXE_BIN" -cp "$SEED/src" -main Main --interp >"$OUT_DIR/eval.stdout"
"$HAXE_BIN" -cp "$SEED/src" -main Main -neko "$OUT_DIR/oracle.n"
neko "$OUT_DIR/oracle.n" >"$OUT_DIR/neko.stdout"

for route in eval neko; do
	if ! diff -u "$SEED/expected.stdout" "$OUT_DIR/$route.stdout"; then
		echo "REFLAXE_OCAML_BYTES_FLOAT_ORACLE:FAIL route=$route" >&2
		exit 1
	fi
done

echo "REFLAXE_OCAML_BYTES_FLOAT_ORACLE:PASS routes=2"
