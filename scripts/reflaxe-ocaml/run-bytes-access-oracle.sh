#!/usr/bin/env bash
set -euo pipefail

# Confirms the public Haxe 4.3.7 Bytes behavior used by the target-qualified
# reflaxe.ocaml access contract. Eval and Neko intentionally expose different
# errors for null multi-byte arguments, so the fixture asserts each route's
# exact failure while sharing the value, evaluation-order, and no-mutation
# checks.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
SRC_DIR="$ROOT/test/reflaxe_ocaml_bytes_access_plan/src"
OUT_DIR="${REFLAXE_OCAML_BYTES_ACCESS_ORACLE_OUT_DIR:-$ROOT/.tmp/reflaxe-ocaml-bytes-access-oracle}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
	echo "reflaxe.ocaml Bytes-access oracle: missing Haxe compiler '$HAXE_BIN'" >&2
	exit 127
fi
if ! command -v neko >/dev/null 2>&1; then
	echo "reflaxe.ocaml Bytes-access oracle: missing Neko" >&2
	exit 127
fi

HAXE_VERSION="$("$HAXE_BIN" --version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "reflaxe.ocaml Bytes-access oracle: expected upstream Haxe 4.3.7, got '$HAXE_VERSION'" >&2
	exit 2
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"$HAXE_BIN" -cp "$SRC_DIR" -main BytesAccessCases --interp
"$HAXE_BIN" -cp "$SRC_DIR" -main BytesAccessCases -neko "$OUT_DIR/oracle.n"
neko "$OUT_DIR/oracle.n"

echo "REFLAXE_OCAML_BYTES_ACCESS_ORACLE:PASS routes=2"
