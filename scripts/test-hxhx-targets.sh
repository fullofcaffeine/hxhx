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

echo "== Building hxhx macro host (RPC skeleton)"
HXHX_MACRO_HOST_EXE="$(HXHX_MACRO_HOST_EXTRA_CP="$ROOT/examples/hxhx-macros/src" HXHX_MACRO_HOST_ENTRYPOINTS="hxhxmacros.ExternalMacros.external();Macro.init()" "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
if [ -z "$HXHX_MACRO_HOST_EXE" ] || [ ! -f "$HXHX_MACRO_HOST_EXE" ]; then
  echo "Missing built executable from build-hxhx-macro-host.sh (expected a path to an .exe)." >&2
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
out="$(HAXE_STD_PATH="$tmpdir/fake_std" "$HXHX_BIN" --hxhx-stage1 "$tmpdir/build.hxml")"
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

echo "== Stage1 bring-up: import_missing is fatal"
cat >"$tmpdir/src/MainMissing.hx" <<'HX'
package;

import DoesNotExist;

class MainMissing {
  static function main() {}
}
HX
set +e
out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main MainMissing --no-output 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected missing import to fail, but stage1 succeeded." >&2
  exit 1
fi
echo "$out" | grep -q "hxhx(stage1): import_missing DoesNotExist"

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

echo "== Stage1 bring-up: module wildcard import trims to base module"
cat >"$tmpdir/src/pack/Wild.hx" <<'HX'
package pack;

class Wild {}
class WildSub {}
HX
cat >"$tmpdir/src/MainWildcard.hx" <<'HX'
package;

import pack.Wild.*;

class MainWildcard {
  static function main() {}
}
HX
out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main MainWildcard --no-output)"
echo "$out" | grep -q "^stage1=ok$"
echo "$out" | grep -vq "stage1=warn import_wildcard pack.Wild.*"

echo "== Stage1 bring-up: toplevel main module (no class)"
cat >"$tmpdir/src/ToplevelMain.hx" <<'HX'
package;

function main() {}
HX
out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main ToplevelMain --no-output)"
echo "$out" | grep -q "^stage1=ok$"

echo "== Stage3 bring-up: type+emit+build minimal OCaml subset"
stage3_out="$tmpdir/out_stage3"
out="$("$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/examples/hih-compiler/fixtures/src" -main demo.A --hxhx-out "$stage3_out")"
echo "$out" | grep -q "^stage3=ok$"
exe="$(echo "$out" | sed -n 's/^exe=//p' | tail -n 1)"
test -n "$exe"
test -f "$exe"

echo "== Stage3 bring-up: type-only checks full graph"
type_only_out="$tmpdir/out_stage3_type_only"
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-type-only -cp "$ROOT/examples/hih-compiler/fixtures/src" -main demo.A --hxhx-out "$type_only_out")"
echo "$out" | grep -q "^resolved_modules="
echo "$out" | grep -q "^typed_modules="
echo "$out" | grep -q "^header_only_modules=0$"
echo "$out" | grep -q "^parsed_methods_total=8$"
echo "$out" | grep -q "^stage3=type_only_ok$"
test ! -f "$type_only_out/out.exe"

echo "== Stage3 bring-up: runs --macro via macro host (allowlist)"
stage3_out2="$tmpdir/out_stage3_macro"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/examples/hih-compiler/fixtures/src" -main demo.A -D HXHX_FLAG=ok --macro 'BuiltinMacros.readFlag()' --macro 'BuiltinMacros.smoke()' --macro 'BuiltinMacros.genModule()' --macro 'BuiltinMacros.dumpDefines()' --macro 'BuiltinMacros.registerHooks()' --hxhx-out "$stage3_out2")"
echo "$out" | grep -q "^macro_run\\[0\\]=flag=ok$"
echo "$out" | grep -q "^macro_run\\[1\\]=smoke:type=builtin:String;define=yes$"
echo "$out" | grep -q "^macro_run\\[2\\]=genModule=ok$"
echo "$out" | grep -q "^macro_run\\[3\\]=defines:flag_map=ok;flag_get=ok;enum_map=1;enum_get=1$"
echo "$out" | grep -q "^macro_run\\[4\\]=hooks=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_SMOKE\\]=1$"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^hook_afterTyping\\[0\\]=ok$"
echo "$out" | grep -q "^hook_onGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^macro_define2\\[HXHX_AFTER_TYPING\\]=1$"
echo "$out" | grep -q "^macro_define2\\[HXHX_ON_GENERATE\\]=1$"
test -f "$stage3_out2/HxHxGen.ml"
grep -q 'builtin:String' "$stage3_out2/HxHxGen.ml"
test -f "$stage3_out2/HxHxHook.ml"

echo "== Stage3 bring-up: runs a non-builtin macro module compiled into the macro host"
stage3_out3="$tmpdir/out_stage3_external"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/examples/hih-compiler/fixtures/src" -main demo.A -D HXHX_FLAG=ok --macro 'hxhxmacros.ExternalMacros.external()' --hxhx-out "$stage3_out3")"
echo "$out" | grep -q "^macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_EXTERNAL\\]=1$"
echo "$out" | grep -q "^stage3=ok$"
test -f "$stage3_out3/HxHxExternal.ml"
grep -q 'external_flag' "$stage3_out3/HxHxExternal.ml"

echo "== Stage3 bring-up: upstream-ish Macro.init() compiles + runs (haxe.macro.Context override)"
stage3_out4="$tmpdir/out_stage3_upstream_macro"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/examples/hih-compiler/fixtures/src" -main demo.A --macro 'Macro.init()' --hxhx-out "$stage3_out4")"
echo "$out" | grep -q "^macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^hook_onGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^stage3=ok$"

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

echo "== Stage3 bring-up: macro-added classpath affects import resolution"
tmpcp="$tmpdir/cp_test"
mkdir -p "$tmpcp/src" "$tmpcp/extra"
cat >"$tmpcp/src/Main.hx" <<'HX'
package;

import Extra;

class Main {
  static function main() {
    return 0;
  }
}
HX
cat >"$tmpcp/extra/Extra.hx" <<'HX'
class Extra {}
HX

set +e
out="$("$HXHX_BIN" --hxhx-stage3 -cp "$tmpcp/src" -main Main --hxhx-out "$tmpcp/out_no_cp" 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected missing import to fail, but stage3 succeeded." >&2
  exit 1
fi
echo "$out" | grep -q "import_missing Extra"

out="$(HXHX_ADD_CP="$tmpcp/extra" HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-stage3 -cp "$tmpcp/src" -main Main --macro 'BuiltinMacros.addCpFromEnv()' --hxhx-out "$tmpcp/out_with_cp")"
echo "$out" | grep -q "^macro_run\\[0\\]=addCp=ok$"
echo "$out" | grep -q "^stage3=ok$"

echo "== Stage3 bring-up: macro emits Haxe module that resolves an import"
tmpgen="$tmpdir/hxgen_test"
mkdir -p "$tmpgen/src"
cat >"$tmpgen/src/Main.hx" <<'HX'
package;

import Gen;

class Main {
  static function main() {
    return 0;
  }
}
HX

set +e
out="$("$HXHX_BIN" --hxhx-stage3 -cp "$tmpgen/src" -main Main --hxhx-out "$tmpgen/out_no_macro" 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected missing import to fail, but stage3 succeeded." >&2
  exit 1
fi
echo "$out" | grep -q "import_missing Gen"

out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-stage3 -cp "$tmpgen/src" -main Main --macro 'BuiltinMacros.genHxModule()' --hxhx-out "$tmpgen/out_with_macro")"
echo "$out" | grep -q "^macro_run\\[0\\]=genHx=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_HXGEN\\]=1$"
echo "$out" | grep -q "^stage3=ok$"
test -f "$tmpgen/out_with_macro/_gen_hx/Gen.hx"

echo "== Stage4 bring-up: macro host RPC handshake + stub Context/Compiler calls"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-macro-selftest)"
echo "$out" | grep -q "^macro_host=ok$"
echo "$out" | grep -q "^macro_ping=pong$"
echo "$out" | grep -q "^macro_define=ok$"
echo "$out" | grep -q "^macro_defined=yes$"
echo "$out" | grep -q "^macro_definedValue=bar$"

echo "== Stage4 bring-up: duplex define roundtrip via macro.run"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-macro-run 'BuiltinMacros.smoke()')"
echo "$out" | grep -q "^macro_run=smoke:type=builtin:String;define=yes$"

echo "== Stage4 bring-up: macro.run builtin entrypoint"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-macro-run "hxhxmacrohost.BuiltinMacros.smoke()")"
echo "$out" | grep -q "^macro_run=smoke:type=builtin:String;define=yes$"
echo "$out" | grep -q "^OK hxhx macro run$"

echo "== Stage4 bring-up: macro.run errors include position payload"
set +e
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-macro-run "hxhxmacrohost.BuiltinMacros.fail()" 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected macro.run failure, but command succeeded." >&2
  exit 1
fi
echo "$out" | grep -q "BuiltinMacros.hx:"

echo "== Stage4 bring-up: context.getType stub"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" "$HXHX_BIN" --hxhx-macro-get-type String)"
echo "$out" | grep -q "^macro_getType=builtin:String$"
echo "$out" | grep -q "^OK hxhx macro getType$"

echo "OK: hxhx target presets"
