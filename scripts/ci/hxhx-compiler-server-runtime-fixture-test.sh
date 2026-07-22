#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v ocamlc >/dev/null 2>&1; then
	echo "Skipping hxhx compiler-server runtime fixture: ocamlc not found on PATH."
	exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cp "$ROOT/packages/reflaxe.ocaml/std/runtime/HxHxCompilerServer.ml" "$tmpdir/HxHxCompilerServer.ml"
cp "$ROOT/test/fixtures/hxhx_compiler_server_runtime/Fixture.ml" "$tmpdir/Fixture.ml"

(
	cd "$tmpdir"
	ocamlc -I +unix -o fixture.exe unix.cma HxHxCompilerServer.ml Fixture.ml
	./fixture.exe
)
