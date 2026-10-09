#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-$ROOT/node_modules/.bin/haxe}"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/shared-construction-stock.XXXXXX")"
cleanup() {
	local status="$?"
	if [[ "$status" -ne 0 ]]; then
		echo "shared_construction_failure_artifacts=$WORK_ROOT" >&2
		return "$status"
	fi
	rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

cd "$ROOT"
"$HAXE_BIN" test/reflaxe_ocaml_shared_construction/test.hxml
cd test/reflaxe_ocaml_shared_construction
"$HAXE_BIN" -cp source -cp src -main Main --no-output --macro 'ConstructorInputPhaseFixture.install()'
"$HAXE_BIN" -cp source -main Main --interp > "$WORK_ROOT/upstream.stdout"
diff -u expected.stdout "$WORK_ROOT/upstream.stdout"
"$HAXE_BIN" stock.hxml -D "ocaml_output=$WORK_ROOT/out"
cd "$WORK_ROOT/out"
dune build ./out.exe
./_build/default/out.exe > "$WORK_ROOT/native.stdout"
diff -u "$ROOT/test/reflaxe_ocaml_shared_construction/expected.stdout" "$WORK_ROOT/native.stdout"
echo 'REFLAXE_OCAML_SHARED_CONSTRUCTION_STOCK_LIFECYCLE:PASS'
