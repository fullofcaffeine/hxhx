#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx target preset tests: dune/ocamlc not found on PATH."
  exit 0
fi

echo "== Building hxhx"
HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Missing built executable from build-hxhx.sh (expected a path to an .exe)." >&2
  exit 1
fi

echo "== Listing targets"
targets="$("$HXHX_BIN" --hxhx-list-targets)"
echo "$targets" | grep -qx "ocaml"

echo "== Preset injects missing flags (compile smoke)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/src"
cat >"$tmpdir/src/Main.hx" <<'HX'
package;

import pkg.*;
import haxe.io.Path as HxPath;
import Util;
using StringTools;

class Main {
  static function main() {
    Util.ping();
    Sys.println("ok");
  }
}
HX

cat >"$tmpdir/src/Util.hx" <<'HX'
class Util {
  public static function ping() {}
}
HX

(
  cd "$ROOT"
  rm -rf out
  HAXE_BIN="${HAXE_BIN:-haxe}" "$HXHX_BIN" --target ocaml -cp "$tmpdir/src" -main Main --no-output -D ocaml_no_build
)

test -f "$ROOT/out/dune"
rm -rf "$ROOT/out"

echo "== Stage1 bring-up: --no-output parse+resolve (no stage0)"
out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main Main --no-output -D stage1_test=1 -lib reflaxe.ocaml --macro 'trace(\"ignored\")')"
echo "$out" | grep -q "^stage1=ok$"

echo "== Stage1 bring-up: accepts .hxml"
cat >"$tmpdir/build.hxml" <<HX
# Minimal Stage1 build file
-cp $tmpdir/src
-main Main
--no-output
HX
out="$("$HXHX_BIN" --hxhx-stage1 "$tmpdir/build.hxml")"
echo "$out" | grep -q "^stage1=ok$"

echo "== Stage1 bring-up: rejects --next"
cat >"$tmpdir/build_next.hxml" <<HX
-cp $tmpdir/src
-main Main
--no-output
--next
HX
set +e
out="$("$HXHX_BIN" --hxhx-stage1 "$tmpdir/build_next.hxml" 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected failure, but stage1 succeeded." >&2
  exit 1
fi
echo "$out" | grep -q "unsupported hxml directive: --next"

echo "== Contradiction fails fast"
set +e
out="$("$HXHX_BIN" --target ocaml -D reflaxe-target=elixir --no-output 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected failure, but command succeeded." >&2
  exit 1
fi
echo "$out" | grep -q "Contradiction"

echo "OK: hxhx target presets"
