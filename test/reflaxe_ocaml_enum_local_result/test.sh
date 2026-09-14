#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
haxe_bin="${HAXE_BIN:-$root/node_modules/.bin/haxe}"
output=.tmp/reflaxe-ocaml-enum-local-result
fixture=test/reflaxe_ocaml_enum_local_result
mkdir -p "$output"
"$haxe_bin" -cp "$fixture" --run EnumReturnProbe > "$output/upstream.stdout"
diff -u "$fixture/expected.stdout" "$output/upstream.stdout"
node scripts/dev/run-with-timeout-heartbeat.js \
  --timeout 300 --heartbeat 30 --label enum-local-result \
  --log "$output/build.log" -- "$haxe_bin" "$fixture/build.hxml"
"$output/out/_build/default/out.exe" > "$output/native.stdout"
diff -u "$fixture/expected.stdout" "$output/native.stdout"
ocamlc -I "$output/out/_build/default/.out.eobjs/byte" \
  -I "$output/out/_build/default/runtime/.hx_runtime.objs/byte" \
  -i "$output/out/Reader.ml" > "$output/Reader.interface"
if ! grep -Eq '^val parse : .* -> Payload[.]payload$' "$output/Reader.interface"; then
  echo 'Reader.parse lost its declared concrete enum result.' >&2
  cat "$output/Reader.interface" >&2
  exit 1
fi
# This fixture deliberately retains one named local across an observable effect.
if grep -Eq 'let value = Obj[.](magic|obj)' "$output/out/Reader.ml"; then
  echo 'The retained enum local still uses an unsafe representation conversion.' >&2
  exit 1
fi
echo 'REFLAXE_OCAML_ENUM_LOCAL_RESULT:PASS'
