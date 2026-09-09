#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"

# Public inspection must accept the exception-only proof without demanding a
# general field-layout representation for this source type.
"$HAXE_BIN" -cp "$ROOT/packages/reflaxe.ocaml/src" \
  --macro 'nullSafety("reflaxe.ocaml")' \
  --run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
  inspect --project "$PWD" --output out --require-lowering --json
