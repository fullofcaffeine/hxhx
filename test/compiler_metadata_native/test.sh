#!/usr/bin/env bash
set -euo pipefail

# Build and observe the real native readers; generation alone is not a pass.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
node scripts/dev/run-with-timeout-heartbeat.js \
  --timeout 900 --heartbeat 30 \
  --log .tmp/compiler-metadata-native/build.log \
  --label compiler-metadata-native \
  -- "${HAXE_BIN:-haxe}" test/compiler_metadata_native/build.hxml
.tmp/compiler-metadata-native/out/_build/default/out.exe > .tmp/compiler-metadata-native/actual.stdout
diff -u test/compiler_metadata_native/expected.stdout .tmp/compiler-metadata-native/actual.stdout

# A successful run must not hide an erased or unconstrained native parser API.
ocamlc \
  -I .tmp/compiler-metadata-native/out/_build/default/.out.eobjs/byte \
  -I .tmp/compiler-metadata-native/out/_build/default/runtime/.hx_runtime.objs/byte \
  -i .tmp/compiler-metadata-native/out/hxhx_CompilerJsonParser.ml \
  > .tmp/compiler-metadata-native/parser.interface
if ! grep -Fxq 'val parse : string -> Hxhx_CompilerJsonValue.compilerjsonvalue' .tmp/compiler-metadata-native/parser.interface; then
  echo 'Compiler JSON parser must return its concrete native value type.' >&2
  cat .tmp/compiler-metadata-native/parser.interface >&2
  exit 1
fi
