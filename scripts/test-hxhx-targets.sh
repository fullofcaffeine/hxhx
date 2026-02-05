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
mkdir -p "$tmpdir/fake_std/haxe/io"
cat >"$tmpdir/fake_std/haxe/io/Path.hx" <<'HX'
package haxe.io;

class Path {}
HX
cat >"$tmpdir/fake_std/StringTools.hx" <<'HX'
class StringTools {}
HX
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
out="$("$HXHX_BIN" --hxhx-stage1 --std "$tmpdir/fake_std" --class-path "$tmpdir/src" --main Main --no-output -D stage1_test=1 --library reflaxe.ocaml --macro 'trace(\"ignored\")')"
echo "$out" | grep -q "^stage1=ok$"
echo "$out" | grep -vq "stage1=warn import_missing haxe.io.Path"
echo "$out" | grep -vq "stage1=warn import_missing StringTools"

echo "== Stage1 bring-up: infer std from env (HAXE_STD_PATH)"
out="$(HAXE_STD_PATH="$tmpdir/fake_std" "$HXHX_BIN" --hxhx-stage1 --class-path "$tmpdir/src" --main Main --no-output)"
echo "$out" | grep -q "^stage1=ok$"
echo "$out" | grep -vq "stage1=warn import_missing haxe.io.Path"
echo "$out" | grep -vq "stage1=warn import_missing StringTools"

echo "== Stage1 bring-up: accepts .hxml"
cat >"$tmpdir/build.hxml" <<HX
# Minimal Stage1 build file
-cp $tmpdir/src
-main Main
--no-output
HX
out="$("$HXHX_BIN" --hxhx-stage1 "$tmpdir/build.hxml")"
echo "$out" | grep -q "^stage1=ok$"

echo "== Stage1 bring-up: .hxml relative -cp"
mkdir -p "$tmpdir/proj/src"
cat >"$tmpdir/proj/src/Main.hx" <<'HX'
class Main {
  static function main() {}
}
HX
cat >"$tmpdir/proj/build_rel.hxml" <<'HX'
-cp src
-main Main
--no-output
HX
out="$("$HXHX_BIN" --hxhx-stage1 "$tmpdir/proj/build_rel.hxml")"
echo "$out" | grep -q "^stage1=ok$"

echo "== Stage1 bring-up: -C / --cwd"
mkdir -p "$tmpdir/proj_cwd/src"
cat >"$tmpdir/proj_cwd/src/Main.hx" <<'HX'
class Main {
  static function main() {}
}
HX
out="$("$HXHX_BIN" --hxhx-stage1 -C "$tmpdir/proj_cwd" -cp src -main Main --no-output)"
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

echo "== Stage1 bring-up: transitive import closure"
cat >"$tmpdir/src/Main2.hx" <<'HX'
package;

import A2;

class Main2 {
  static function main() {}
}
HX

cat >"$tmpdir/src/A2.hx" <<'HX'
package;

import B2;

class A2 {}
HX

cat >"$tmpdir/src/B2.hx" <<'HX'
package;

class B2 {
HX

set +e
out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main Main2 --no-output 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected transitive import failure, but stage1 succeeded." >&2
  exit 1
fi
echo "$out" | grep -q 'parse failed for import "B2"'

echo "== Stage1 bring-up: import-only module (no class)"
cat >"$tmpdir/src/TypesOnly.hx" <<'HX'
package;

typedef Foo = { x:Int };
HX

cat >"$tmpdir/src/Main3.hx" <<'HX'
package;

import TypesOnly;

class Main3 {
  static function main() {}
}
HX

out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main Main3 --no-output)"
echo "$out" | grep -q "^stage1=ok$"

echo "== Stage1 bring-up: import subtype resolves to module file"
mkdir -p "$tmpdir/src/pack"
cat >"$tmpdir/src/pack/Mod.hx" <<'HX'
package pack;

class Mod {}
class SubType {}
HX
cat >"$tmpdir/src/Main4.hx" <<'HX'
package;

import pack.Mod.SubType;

class Main4 {
  static function main() {}
}
HX
out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main Main4 --no-output)"
echo "$out" | grep -q "^stage1=ok$"
echo "$out" | grep -vq "stage1=warn import_missing pack.Mod.SubType"

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
