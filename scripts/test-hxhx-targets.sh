#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx target preset tests: dune/ocamlc not found on PATH."
  exit 0
fi

if ! command -v ocamlopt >/dev/null 2>&1; then
  echo "Skipping hxhx Stage3 tests: ocamlopt not found on PATH."
fi

HXHX_BIN="${HXHX_BIN:-}"
if [ -n "$HXHX_BIN" ]; then
  echo "== Using prebuilt hxhx binary: $HXHX_BIN"
else
  echo "== Building hxhx"
  HXHX_BIN_RAW="$(
    HXHX_FORCE_STAGE0="${HXHX_FORCE_STAGE0:-1}" \
    "$ROOT/scripts/hxhx/build-hxhx.sh"
  )"
  HXHX_BIN="$(printf "%s\n" "$HXHX_BIN_RAW" | tail -n 1)"
  if [ "$HXHX_BIN_RAW" != "$HXHX_BIN" ]; then
    echo "Regression: build-hxhx.sh must print only the binary path on stdout." >&2
    echo "build-hxhx.sh stdout was:" >&2
    printf "%s\n" "$HXHX_BIN_RAW" >&2
    exit 1
  fi
fi
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Missing hxhx executable (set HXHX_BIN or allow build-hxhx.sh to produce one)." >&2
  exit 1
fi

echo "== Building hxhx macro host (RPC skeleton)"
# By default this uses the committed Stage4 bootstrap snapshot under:
#   tools/hxhx-macro-host/bootstrap_out
# so `npm test` can run without a stage0 `haxe` binary on PATH.
HXHX_MACRO_HOST_EXE="$("$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
if [ -z "$HXHX_MACRO_HOST_EXE" ] || [ ! -f "$HXHX_MACRO_HOST_EXE" ]; then
  echo "Missing built executable from build-hxhx-macro-host.sh (expected a path to an .exe)." >&2
  exit 1
fi

# The Stage3 auto-build test rebuilds the macro host in-place (same output path),
# which can clobber the entrypoint allowlist for subsequent tests. Copy the
# freshly built host to a stable temp path so the rest of this script remains
# deterministic.
macrohost_tmp="$(mktemp -d)"
trap 'rm -f "${mini_hxml:-}" "${legacy_log:-}" "${strict_log:-}" "${strict_sep_log:-}" "${trycatch_log:-}"; rm -rf "${tmpdir:-}" "$macrohost_tmp"' EXIT
HXHX_MACRO_HOST_EXE_STABLE="$macrohost_tmp/hxhx-macro-host"
cp "$HXHX_MACRO_HOST_EXE" "$HXHX_MACRO_HOST_EXE_STABLE"
chmod +x "$HXHX_MACRO_HOST_EXE_STABLE"

echo "== Stage4 bring-up: macro host autodiscovery (sibling binary)"
tmpbin="$(mktemp -d)"
cp "$HXHX_BIN" "$tmpbin/hxhx"
chmod +x "$tmpbin/hxhx"
cp "$HXHX_MACRO_HOST_EXE_STABLE" "$tmpbin/hxhx-macro-host"
chmod +x "$tmpbin/hxhx-macro-host"
out="$(
  HXHX_MACRO_HOST_EXE="" "$tmpbin/hxhx" --hxhx-macro-selftest
)"
echo "$out" | grep -q "^macro_host=ok$"
echo "$out" | grep -q "^OK hxhx macro rpc$"
rm -rf "$tmpbin"

echo "== Listing targets"
targets="$("$HXHX_BIN" --hxhx-list-targets)"
echo "$targets" | grep -qx "ocaml"
echo "$targets" | grep -qx "ocaml-stage3"
echo "$targets" | grep -qx "js"
echo "$targets" | grep -qx "js-native"

echo "== Unsupported legacy target presets fail fast"
legacy_log="$(mktemp)"
if "$HXHX_BIN" --target flash >"$legacy_log" 2>&1; then
  echo "Expected --target flash to fail with unsupported-target message." >&2
  exit 1
fi
grep -q 'Target "flash" is not supported in hxhx' "$legacy_log"
grep -q "Legacy Flash/AS3 targets are intentionally unsupported" "$legacy_log"
if "$HXHX_BIN" --target as3 >"$legacy_log" 2>&1; then
  echo "Expected --target as3 to fail with unsupported-target message." >&2
  exit 1
fi
grep -q 'Target "as3" is not supported in hxhx' "$legacy_log"
grep -q "Legacy Flash/AS3 targets are intentionally unsupported" "$legacy_log"
if "$HXHX_BIN" --swf "$legacy_log.swf" >"$legacy_log" 2>&1; then
  echo "Expected --swf to fail with unsupported-target message." >&2
  exit 1
fi
grep -q 'Target "flash" is not supported in this implementation' "$legacy_log"
grep -q "Legacy Flash/AS3 targets are intentionally unsupported" "$legacy_log"
if "$HXHX_BIN" --as3 "$legacy_log.as3" >"$legacy_log" 2>&1; then
  echo "Expected --as3 to fail with unsupported-target message." >&2
  exit 1
fi
grep -q 'Target "as3" is not supported in this implementation' "$legacy_log"
grep -q "Legacy Flash/AS3 targets are intentionally unsupported" "$legacy_log"

echo "== Stage0 delegation guard: blocks shim delegation"
if HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --version >"$legacy_log" 2>&1; then
  echo "Expected HXHX_FORBID_STAGE0=1 to block stage0 passthrough (--version)." >&2
  exit 1
fi
grep -q "HXHX_FORBID_STAGE0=1 forbids stage0 delegation" "$legacy_log"

echo "== Preset injects missing flags (compile smoke)"
tmpdir="$(mktemp -d)"

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

cat >"$tmpdir/src/JsNativeMain.hx" <<'HX'
class JsNativeMain {
  static function main() {
    var sum = 0;
    for (i in 0...3) {
      sum = sum + i;
    }
    if (sum > 0) {
      sum = sum + sum;
    }
    Sys.println("js-native:" + sum);
  }
}
HX

cat >"$tmpdir/src/JsNativeCompoundAssignMain.hx" <<'HX'
class JsNativeCompoundAssignMain {
  static function main() {
    var acc = 1;
    acc += 5;
    acc *= 2;
    acc -= 3;
    acc <<= 1;
    acc >>= 2;
    acc |= 8;
    acc ^= 3;
    acc &= 15;

    var unsigned = -1;
    unsigned >>>= 30;

    Sys.println("js-native-compound:" + acc + ":" + unsigned);
  }
}
HX

cat >"$tmpdir/src/JsNativeIncDecMain.hx" <<'HX'
class JsNativeIncDecMain {
  static function main() {
    var i = 0;
    while (i < 4) {
      i++;
    }

    var j = 4;
    while (j > 1) {
      --j;
    }

    var k = 1;
    k++;
    ++k;
    k--;
    --k;

    Sys.println("js-native-incdec:" + i + ":" + j + ":" + k);
  }
}
HX

cat >"$tmpdir/src/JsNativeEnumReflectionMain.hx" <<'HX'
class JsNativeEnumReflectionMain {
  static function main() {
    var mode = Run;
    var label = "none";
    switch (mode) {
      case Build:
        label = "build";
      case Run:
        label = "run";
      default:
        label = "other";
    }

    var cls = Type.resolveClass("JsNativeEnumReflectionMain");
    Sys.println("enum-switch:" + label);
    Sys.println("class-name:" + Type.getClassName(cls));
    Sys.println("enum-ctor:" + Type.enumConstructor(mode));
    Sys.println("enum-params:" + Type.enumParameters(mode).length);
  }
}
HX

cat >"$tmpdir/src/JsNativeTryCatchMain.hx" <<'HX'
class JsNativeTryCatchMain {
  static function main() {
    var msg = "start";
    try {
      throw "boom";
    } catch (err:Dynamic) {
      msg = "caught:" + err;
      try {
        throw err;
      } catch (inner:Dynamic) {
        msg = msg + "|rethrow:" + inner;
      }
    }
    Sys.println(msg);
  }
}
HX

cat >"$tmpdir/src/StrictCliMain.hx" <<'HX'
class StrictCliMain {
  static function main() {}
}
HX

(
  cd "$ROOT"
  rm -rf out
  HAXE_BIN="${HAXE_BIN:-haxe}" "$HXHX_BIN" --target ocaml -cp "$tmpdir/src" -main Main --no-output -D ocaml_no_build
)

test -f "$ROOT/out/dune"
rm -rf "$ROOT/out"

echo "== Builtin fast-path target: linked Stage3 backend without --library"
cat >"$tmpdir/src/BuiltinMain.hx" <<'HX'
class BuiltinMain {
  static function main() {}
}
HX
out="$(HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target ocaml-stage3 --hxhx-no-emit -cp "$tmpdir/src" -main BuiltinMain --hxhx-out "$tmpdir/out_builtin_fast")"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Stage0 delegation guard: builtin target path remains allowed"
out="$(HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target ocaml-stage3 --hxhx-no-emit -cp "$tmpdir/src" -main BuiltinMain --hxhx-out "$tmpdir/out_builtin_guard")"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Strict CLI mode: rejects hxhx-only flags"
strict_log="$(mktemp)"
if "$HXHX_BIN" --hxhx-strict-cli --target js -cp "$tmpdir/src" -main JsNativeMain --no-output >"$strict_log" 2>&1; then
  echo "Expected strict CLI mode to reject --target." >&2
  exit 1
fi
grep -q "strict CLI mode rejects non-upstream flag: --target" "$strict_log"

if "$HXHX_BIN" --hxhx-strict-cli --hxhx-stage3 --hxhx-no-emit -cp "$tmpdir/src" -main JsNativeMain >"$strict_log" 2>&1; then
  echo "Expected strict CLI mode to reject --hxhx-stage3." >&2
  exit 1
fi
grep -q "strict CLI mode rejects non-upstream flag: --hxhx-stage3" "$strict_log"

echo "== Strict CLI mode: allows upstream-style flags"
"$HXHX_BIN" --hxhx-strict-cli --js "$tmpdir/strict_cli_ok.js" -cp "$tmpdir/src" -main StrictCliMain --no-output >/dev/null

echo "== Strict CLI mode: ignores forwarded args after --"
strict_sep_log="$(mktemp)"
"$HXHX_BIN" --hxhx-strict-cli -- --target js >"$strict_sep_log" 2>&1 || true
if grep -q "strict CLI mode rejects non-upstream flag" "$strict_sep_log"; then
  echo "Strict CLI mode should not parse args after -- separator." >&2
  exit 1
fi
grep -q -- "--target" "$strict_sep_log"

echo "== Strict CLI mode: keeps legacy unsupported target errors explicit"
if "$HXHX_BIN" --hxhx-strict-cli --swf "$tmpdir/strict_legacy.swf" >"$strict_log" 2>&1; then
  echo "Expected --swf to remain unsupported in strict mode." >&2
  exit 1
fi
grep -q 'Target "flash" is not supported in this implementation' "$strict_log"

echo "== Builtin fast-path target: linked JS backend preset (no-emit)"
out="$(HXHX_TRACE_BACKEND_SELECTION=1 HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --hxhx-no-emit -cp "$tmpdir/src" -main JsNativeMain --hxhx-out "$tmpdir/out_js_native_fast")"
echo "$out" | grep -q "^backend_selected_impl=builtin/js-native$"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Builtin fast-path target: dynamic provider entrypoint can override backend selection"
out="$(HXHX_TRACE_BACKEND_SELECTION=1 HXHX_BACKEND_PROVIDERS=backend.js.JsBackend HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --hxhx-no-emit -cp "$tmpdir/src" -main JsNativeMain --hxhx-out "$tmpdir/out_js_native_provider")"
echo "$out" | grep -q "^backend_selected_impl=provider/js-native-wrapper$"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Builtin fast-path target: linked JS backend emits and runs"
out="$(HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --js "$tmpdir/out_js_native_emit/main.js" -cp "$tmpdir/src" -main JsNativeMain --hxhx-out "$tmpdir/out_js_native_emit")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^artifact=$tmpdir/out_js_native_emit/main.js$"
echo "$out" | grep -q "^run=ok$"
echo "$out" | grep -q "^js-native:6$"
test -f "$tmpdir/out_js_native_emit/main.js"

echo "== Builtin fast-path target: js-native compound assignment expressions"
out="$(HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --js "$tmpdir/out_js_native_compound/main.js" -cp "$tmpdir/src" -main JsNativeCompoundAssignMain --hxhx-out "$tmpdir/out_js_native_compound")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^artifact=$tmpdir/out_js_native_compound/main.js$"
echo "$out" | grep -q "^run=ok$"
echo "$out" | grep -q "^js-native-compound:6:3$"
test -f "$tmpdir/out_js_native_compound/main.js"

echo "== Builtin fast-path target: js-native increment/decrement expressions"
out="$(HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --js "$tmpdir/out_js_native_incdec/main.js" -cp "$tmpdir/src" -main JsNativeIncDecMain --hxhx-out "$tmpdir/out_js_native_incdec")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^artifact=$tmpdir/out_js_native_incdec/main.js$"
echo "$out" | grep -q "^run=ok$"
echo "$out" | grep -q "^js-native-incdec:4:1:1$"
test -f "$tmpdir/out_js_native_incdec/main.js"

echo "== Builtin fast-path target: --js output path is cwd-relative (Haxe-compatible)"
mkdir -p "$tmpdir/workdir"
out="$(HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --js rel/main.js --cwd "$tmpdir/workdir" -cp "$tmpdir/src" -main JsNativeMain --hxhx-out "$tmpdir/out_js_native_rel")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^artifact=$tmpdir/workdir/rel/main.js$"
echo "$out" | grep -q "^run=ok$"
echo "$out" | grep -q "^js-native:6$"
test -f "$tmpdir/workdir/rel/main.js"

echo "== Builtin fast-path target: js-native enum-switch + basic reflection helpers"
out="$(HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --js "$tmpdir/out_js_enum_reflect/main.js" -cp "$tmpdir/src" -main JsNativeEnumReflectionMain --hxhx-out "$tmpdir/out_js_enum_reflect")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^artifact=$tmpdir/out_js_enum_reflect/main.js$"
echo "$out" | grep -q "^run=ok$"
echo "$out" | grep -q "^enum-switch:run$"
echo "$out" | grep -q "^class-name:JsNativeEnumReflectionMain$"
echo "$out" | grep -q "^enum-ctor:Run$"
echo "$out" | grep -q "^enum-params:0$"
test -f "$tmpdir/out_js_enum_reflect/main.js"

echo "== Builtin fast-path target: js-native try/catch throw/rethrow is explicit unsupported"
trycatch_log="$(mktemp)"
if HAXE_BIN=/definitely-not-used "$HXHX_BIN" --target js-native --js "$tmpdir/out_js_trycatch/main.js" -cp "$tmpdir/src" -main JsNativeTryCatchMain --hxhx-out "$tmpdir/out_js_trycatch" >"$trycatch_log" 2>&1; then
  echo "Expected js-native try/catch throw/rethrow fixture to fail with explicit unsupported marker." >&2
  exit 1
fi
grep -q "js-native MVP does not support expression kind: EUnsupported(throw)" "$trycatch_log"

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

if command -v ocamlopt >/dev/null 2>&1; then
  echo "== Stage3 regression: module-local helper types (multi-class modules)"
  cat >"$tmpdir/src/MultiStage3.hx" <<'HX'
package;

private class Helper {
  public static var answer:Int = 42;
}

class Helper2 {
  public static var answer:Int = 7;
}

class MultiStage3 {
  static function main() {
    // Exercise both resolution shapes:
    // - unqualified helper type (`Helper`)
    // - module-qualified helper type (`MultiStage3.Helper2`)
    //
    // The Stage3 emitter is non-semantic, so the runtime result is irrelevant; this is a
    // link-time regression check that providers for module-local helper types are emitted.
    var a = Helper.answer;
    var b = MultiStage3.Helper2.answer;
    Sys.println(Std.string(a + b));
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_helper" -cp "$tmpdir/src" -main MultiStage3)"
  echo "$out" | grep -q "^stage3=ok$"

  echo "== Stage3 regression: module-local typedef/abstract declarations"
  cat >"$tmpdir/src/TypeDeclStage3.hx" <<'HX'
package;

typedef Box = {
  var value:Int;
}

abstract Flag(Int) {
  public static inline function fromInt(v:Int):Flag {
    return cast v;
  }
}

class TypeDeclStage3 {
  static function main() {
    var b:TypeDeclStage3.Box = { value: 1 };
    var f = TypeDeclStage3.Flag.fromInt(b.value);
    Sys.println(Std.string(cast f));
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_typedecls" -cp "$tmpdir/src" -main TypeDeclStage3)"
  echo "$out" | grep -q "^stage3=ok$"
  test -f "$tmpdir/out_stage3_typedecls/TypeDeclStage3_Box.ml"
  test -f "$tmpdir/out_stage3_typedecls/TypeDeclStage3_Flag.ml"
  grep -q "let fromInt" "$tmpdir/out_stage3_typedecls/TypeDeclStage3_Flag.ml"

  echo "== Stage3 regression: module-local typedef/abstract declarations (forced pure parser)"
  out="$(HIH_FORCE_HX_PARSER=1 "$HXHX_BIN" --hxhx-stage3 --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_typedecls_force" -cp "$tmpdir/src" -main TypeDeclStage3)"
  echo "$out" | grep -q "^stage3=ok$"
  test -f "$tmpdir/out_stage3_typedecls_force/TypeDeclStage3_Box.ml"
  test -f "$tmpdir/out_stage3_typedecls_force/TypeDeclStage3_Flag.ml"
  grep -q "let fromInt" "$tmpdir/out_stage3_typedecls_force/TypeDeclStage3_Flag.ml"

  echo "== Stage3 regression: Sys.environment lowering (HxSys.environment)"
  cat >"$tmpdir/src/SysEnvStage3.hx" <<'HX'
package;

class SysEnvStage3 {
  static function main() {
    final env = Sys.environment();
    // Keep `env` referenced so the lowering stays present in emitted OCaml.
    if (env == null) Sys.println("null");
    Sys.println("ok");
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_sysenv" -cp "$tmpdir/src" -main SysEnvStage3)"
  echo "$out" | grep -q "^stage3=ok$"
  test -f "$tmpdir/out_stage3_sysenv/SysEnvStage3.ml"
  grep -q "HxSys.environment" "$tmpdir/out_stage3_sysenv/SysEnvStage3.ml"

  echo "== Stage3 regression: Sys.args lowering qualifies Stdlib.Array helpers"
  cat >"$tmpdir/src/SysArgsStage3.hx" <<'HX'
package;

class SysArgsStage3 {
  static function main() {
    final args = Sys.args();
    Sys.println(Std.string(args.length));
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_sysargs" -cp "$tmpdir/src" -main SysArgsStage3)"
  echo "$out" | grep -q "^stage3=ok$"
  test -f "$tmpdir/out_stage3_sysargs/SysArgsStage3.ml"
  grep -q "Stdlib.Array.length __argv" "$tmpdir/out_stage3_sysargs/SysArgsStage3.ml"
  grep -q "Stdlib.Array.to_list (Stdlib.Array.sub __argv 1 (__len - 1))" "$tmpdir/out_stage3_sysargs/SysArgsStage3.ml"

  echo "== Stage3 regression: Int64 lowering avoids OCaml Int64.ofInt"
  cat >"$tmpdir/src/Int64FpHelperStage3.hx" <<'HX'
package;

class Int64FpHelperStage3 {
  static function main() {
    var a = haxe.Int64.ofInt(0);
    var b = haxe.Int64.make(1, 2);
    // Keep mutator call-shapes present in emitted OCaml (bring-up no-op rewrite).
    untyped a.set_low(3);
    untyped a.set_high(4);
    Sys.println(Std.string(a));
    Sys.println(Std.string(b));
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_int64_fphelper" -cp "$tmpdir/src" -main Int64FpHelperStage3)"
  echo "$out" | grep -q "^stage3=ok$"
  test -f "$tmpdir/out_stage3_int64_fphelper/Int64FpHelperStage3.ml"
  grep -q "Haxe_Int64.ofInt" "$tmpdir/out_stage3_int64_fphelper/Int64FpHelperStage3.ml"
  grep -q "Haxe_Int64.make" "$tmpdir/out_stage3_int64_fphelper/Int64FpHelperStage3.ml"
  if rg -n "(^|[^A-Za-z0-9_])Int64\\.ofInt\\b" "$tmpdir/out_stage3_int64_fphelper" >/dev/null 2>&1; then
    echo "Stage3 Int64 regression: found bare Int64.ofInt call in emitted OCaml output." >&2
    exit 1
  fi

  echo "== Stage3 regression: native frontend handles regex literals with quote chars"
  cat >"$tmpdir/src/RegexLiteralStage3.hx" <<'HX'
package;

class RegexLiteralStage3 {
  static var rx = ~/[A-Za-z0-9_."-]+/;

  static function main() {
    Sys.println(Std.string(rx.match("abc")));
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_regex_literal" -cp "$tmpdir/src" -main RegexLiteralStage3)"
  echo "$out" | grep -q "^stage3=ok$"

  echo "== Stage3 regression: native frontend accepts keyword-named function declarations"
  cat >"$tmpdir/src/KeywordAsStage3.hx" <<'HX'
package;

class KeywordAsProvider {
  public static inline function as<T>(obj:T, cl:Class<T>):T {
    return obj;
  }
}

class KeywordAsStage3 {
  static function main() {
    Sys.println("ok");
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_keyword_as" -cp "$tmpdir/src" -main KeywordAsStage3)"
  echo "$out" | grep -q "^stage3=ok$"

  echo "== Stage3 regression: #if lines with comment '#' still drive conditional stack"
  cat >"$tmpdir/src/ConditionalHashCommentStage3.hx" <<'HX'
package;

class ConditionalHashCommentStage3 {
  static function main() {
    #if cs // issue #996 style marker should not disable #if parsing
    cs.system.Console.WriteLine("turkey");
    #end
    Sys.println("ok");
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_conditional_hash_comment" -cp "$tmpdir/src" -main ConditionalHashCommentStage3)"
  echo "$out" | grep -q "^stage3=ok$"

  echo "== Stage3 regression: sys.io.Process constructor is async spawn"
  cat >"$tmpdir/src/ProcessSpawnStage3.hx" <<'HX'
package;

class ProcessSpawnStage3 {
  static function main() {
    final p = new sys.io.Process("echo", ["ok"]);
    p.kill();
    p.close();
  }
}
HX

  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_process_spawn" -cp "$tmpdir/src" -main ProcessSpawnStage3)"
  echo "$out" | grep -q "^stage3=ok$"
  test -f "$tmpdir/out_stage3_process_spawn/ProcessSpawnStage3.ml"
  grep -q "HxBootProcess.spawn (\"echo\")" "$tmpdir/out_stage3_process_spawn/ProcessSpawnStage3.ml"
  grep -q "HxBootProcess.kill (p)" "$tmpdir/out_stage3_process_spawn/ProcessSpawnStage3.ml"

  echo "== Stage3 regression: fully-qualified type path without import"
  mkdir -p "$tmpdir/src/fqdep"
  cat >"$tmpdir/src/fqdep/Dep.hx" <<'HX'
package fqdep;

class Dep {
  public static function ping() {}
}
HX
  cat >"$tmpdir/src/FqRefStage3.hx" <<'HX'
package;

class FqRefStage3 {
  static function main() {
    // No import on purpose: exercise `pkg.Type.member(...)` lazy module inclusion.
    fqdep.Dep.ping();
    Sys.println("ok");
  }
}
HX
  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_fqdep" -cp "$tmpdir/src" -main FqRefStage3)"
  echo "$out" | grep -q "^stage3=ok$"

  echo "== Stage3 regression: OCaml keyword escaping for emitted value names"
  cat >"$tmpdir/src/KeywordEscapeStage3.hx" <<'HX'
package;

class KeywordEscapeStage3 {
  static function mod(a:Int, b:Int):Int {
    return a % b;
  }

  static function main() {
    Sys.println(Std.string(mod(5, 2)));
  }
}
HX
  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run --hxhx-out "$tmpdir/out_stage3_keyword_escape" -cp "$tmpdir/src" -main KeywordEscapeStage3)"
  echo "$out" | grep -q "^stage3=ok$"
  grep -q "mod_" "$tmpdir/out_stage3_keyword_escape/KeywordEscapeStage3.ml"

  echo "== Stage3 regression: --display root inference"
  cat >"$tmpdir/src/DisplayMain.hx" <<'HX'
class DisplayMain {
  static function main() {}
}
HX
  out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit --hxhx-out "$tmpdir/out_stage3_display" --display "$tmpdir/src/DisplayMain.hx@0@diagnostics" -cp "$tmpdir/src" --no-output)"
  echo "$out" | grep -q "^stage3=no_emit_ok$"

  echo "== Stage3 regression: --wait stdio frame protocol"
  if command -v python3 >/dev/null 2>&1; then
    HXHX_BIN_FOR_PY="$HXHX_BIN" TMPDIR_FOR_PY="$tmpdir" python3 - <<'PY'
import os
import struct
import subprocess
import sys

hxhx_bin = os.environ["HXHX_BIN_FOR_PY"]
tmpdir = os.environ["TMPDIR_FOR_PY"]
source = os.path.join(tmpdir, "src", "DisplayMain.hx")
out_dir = os.path.join(tmpdir, "out_stage3_wait_stdio")

request_args = [
    "--display", source + "@0@diagnostics",
    "-cp", os.path.join(tmpdir, "src"),
    "--no-output",
]
payload = ("\n".join(request_args) + "\n").encode("utf-8")
frame = struct.pack("<i", len(payload)) + payload

proc = subprocess.Popen(
    [hxhx_bin, "--hxhx-stage3", "--hxhx-no-emit", "--hxhx-out", out_dir, "--wait", "stdio"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

try:
    assert proc.stdin is not None
    assert proc.stderr is not None
    proc.stdin.write(frame)
    proc.stdin.flush()

    header = proc.stderr.read(4)
    if len(header) != 4:
        raise RuntimeError("missing wait-stdio response header")
    size = struct.unpack("<i", header)[0]
    body = proc.stderr.read(size)
    if len(body) != size:
        raise RuntimeError("truncated wait-stdio response body")

    is_error = len(body) > 0 and body[0] == 0x02
    text = body[1:].decode("utf-8", errors="replace") if is_error else body.decode("utf-8", errors="replace")
    if is_error:
        raise RuntimeError("wait-stdio response flagged error: " + text)
    if '[{"diagnostics":[]}]' not in text:
        raise RuntimeError("unexpected wait-stdio diagnostics payload: " + text)
finally:
    if proc.stdin is not None:
        proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
        raise RuntimeError("wait-stdio server did not exit after stdin close")
    if proc.returncode != 0:
        raise RuntimeError(f"wait-stdio server exited with code {proc.returncode}")
PY
  else
    echo "Skipping wait stdio regression: python3 not found on PATH."
  fi

  echo "== Stage3 regression: --wait socket + --connect roundtrip"
  if command -v python3 >/dev/null 2>&1; then
    HXHX_BIN_FOR_PY="$HXHX_BIN" TMPDIR_FOR_PY="$tmpdir" python3 - <<'PY'
import os
import socket
import subprocess
import time

hxhx_bin = os.environ["HXHX_BIN_FOR_PY"]
tmpdir = os.environ["TMPDIR_FOR_PY"]
source = os.path.join(tmpdir, "src", "DisplayMain.hx")
classpath = os.path.join(tmpdir, "src")
out_dir = os.path.join(tmpdir, "out_stage3_wait_socket")

probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
probe.bind(("127.0.0.1", 0))
port = probe.getsockname()[1]
probe.close()

endpoint = f"127.0.0.1:{port}"
server = subprocess.Popen(
    [hxhx_bin, "--hxhx-stage3", "--hxhx-no-emit", "--hxhx-out", out_dir, "--wait", endpoint],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)

try:
    last = None
    for _ in range(40):
        time.sleep(0.1)
        result = subprocess.run(
            [
                hxhx_bin,
                "--hxhx-stage3",
                "--hxhx-no-emit",
                "--hxhx-out",
                out_dir,
                "--connect",
                endpoint,
                "--display",
                source + "@0@diagnostics",
                "-cp",
                classpath,
                "--no-output",
            ],
            capture_output=True,
            text=True,
        )
        last = result
        if result.returncode == 0:
            if '[{"diagnostics":[]}]' not in result.stderr:
                raise RuntimeError("unexpected connect payload: " + result.stderr)
            break
    else:
        raise RuntimeError(
            "connect request never succeeded (last rc=%s, stderr=%s)"
            % (last.returncode if last else "?", last.stderr if last else "")
        )
finally:
    server.terminate()
    try:
        server.wait(timeout=5)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait(timeout=5)
PY
  else
    echo "Skipping wait socket/connect regression: python3 not found on PATH."
  fi
fi

echo "== Stage1 bring-up: multi-class module selects expected class"
cat >"$tmpdir/src/Multi.hx" <<'HX'
package;

class Helper extends Base {
  public function new() {}
}

class Multi {
  public static function main() {}
}
HX
out="$("$HXHX_BIN" --hxhx-stage1 --std "$tmpdir/fake_std" --class-path "$tmpdir/src" --main Multi --no-output)"
echo "$out" | grep -q "^stage1=ok$"

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

echo "== Stage1 bring-up: conditional compilation strips inactive imports"
cat >"$tmpdir/src/CondMain.hx" <<'HX'
package;

#if java
import haxe.test.Base;
#end

class CondMain {
  static function main() {}
}
HX
out="$("$HXHX_BIN" --hxhx-stage1 -cp "$tmpdir/src" -main CondMain --no-output)"
echo "$out" | grep -q "^stage1=ok$"

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
out="$("$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/workloads/hih-compiler/fixtures/src" -main demo.A --hxhx-out "$stage3_out")"
echo "$out" | grep -q "^stage3=ok$"
exe="$(echo "$out" | sed -n 's/^exe=//p' | tail -n 1)"
test -n "$exe"
test -f "$exe"

echo "== Stage3 bring-up: module-local helper class emits provider (Gate1 regression)"
tmphelper="$tmpdir/module_local_helper"
mkdir -p "$tmphelper/src"
cat >"$tmphelper/src/Main.hx" <<'HX'
class Main {
  static function main() {
    // Regression: helper types declared in the same file must still be emitted as OCaml
    // compilation units so static references compile.
    trace(Helper.ANSWER);
  }
}

private class Helper {
  public static final ANSWER = 42;
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmphelper/src" -main Main --hxhx-out "$tmphelper/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: module-local enum abstract emits provider (Gate1 regression)"
tmpenumabs="$tmpdir/module_local_enum_abstract"
mkdir -p "$tmpenumabs/src/pkg"
cat >"$tmpenumabs/src/pkg/MyAbstract.hx" <<'HX'
package pkg;

// Regression fixture: file's module name is `MyAbstract`, but the main type is an abstract (not a class).
// The helper `enum abstract` must still be loadable and must emit an OCaml provider unit.
abstract MyAbstract(Int) {}

enum abstract FakeEnumAbstract(Int) {
  var NotFound = 404;
}
HX

cat >"$tmpenumabs/src/Main.hx" <<'HX'
class Main {
  static function main() {
    // Fully-qualified access to a module-local helper type.
    var _v = pkg.MyAbstract.FakeEnumAbstract.NotFound;
    trace("ok");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpenumabs/src" -main Main --hxhx-out "$tmpenumabs/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: omitted optional args don't partial apply"
tmpopt="$tmpdir/optional_args"
mkdir -p "$tmpopt/src"
cat >"$tmpopt/src/Main.hx" <<'HX'
class Main {
  static function f(a:Int, b:Int, ?c:Int):Int {
    return a;
  }

  static function main() {
    // Bring-up regression: calling a known function with fewer args than its declaration
    // must not emit an OCaml partial application (should fill missing optional/default args).
    f(1, 2);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 -cp "$tmpopt/src" -main Main --hxhx-out "$tmpopt/out")"
echo "$out" | grep -q "^stage3=ok$"

echo "== Stage3 bring-up: emits full bodies (trace prints)"
tmpfull="$tmpdir/full_body"
mkdir -p "$tmpfull/src"
cat >"$tmpfull/src/Main.hx" <<'HX'
class Main {
  static function main() {
    var x = 1;
    if (x + 1 == 3) {
      trace("BAD");
    } else {
      trace("OK");
    }
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpfull/src" -main Main --hxhx-out "$tmpfull/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^OK$"
echo "$out" | grep -vq "^BAD$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 regression: emit-full-bodies works on repeated --hxhx-out reuse"
tmpreuse="$tmpdir/reuse_out"
mkdir -p "$tmpreuse/src"
cat >"$tmpreuse/src/Main.hx" <<'HX'
class Main {
  static function main() {
    var xs = [1, 2, 3];
    trace(xs.length);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run -cp "$tmpreuse/src" -main Main --hxhx-out "$tmpreuse/out")"
echo "$out" | grep -q "^stage3=ok$"
grep -q "HxBootArray.length" "$tmpreuse/out/Main.ml"
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run -cp "$tmpreuse/src" -main Main --hxhx-out "$tmpreuse/out")"
echo "$out" | grep -q "^stage3=ok$"

echo "== Stage3 bring-up: class-scope static finals bind + run"
tmpstaticfinal="$tmpdir/static_final"
mkdir -p "$tmpstaticfinal/src"
cat >"$tmpstaticfinal/src/Main.hx" <<'HX'
class Main {
  static final TRIALS = 3;
  static final SEP = if (Sys.systemName() == "Windows") ";" else ":";

  static function main() {
    for (i in 0...TRIALS) trace(i);
    trace(SEP);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpstaticfinal/src" -main Main --hxhx-out "$tmpstaticfinal/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^0$"
echo "$out" | grep -q "^1$"
echo "$out" | grep -q "^2$"
echo "$out" | grep -qE "^[;:]$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 regression: non-static class fields survive native protocol"
tmpinstfield="$tmpdir/instance_field"
mkdir -p "$tmpinstfield/src"
cat >"$tmpinstfield/src/Main.hx" <<'HX'
class Main {
  var x:Int;

  public function new() {
    this.x = 41;
  }

  function ping() {
    return this.x;
  }

  static function main() {
    var m = new Main();
    m.ping();
  }
}
HX
out="$(HXHX_TYPER_STRICT=1 "$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit --hxhx-emit-full-bodies -cp "$tmpinstfield/src" -main Main --hxhx-out "$tmpinstfield/out")"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Stage3 regression: field access on call results preserves Obj.repr call grouping"
tmprunciobj="$tmpdir/runci_call_result_field_access"
mkdir -p "$tmprunciobj/src"
cat >"$tmprunciobj/src/Main.hx" <<'HX'
class Box {
  public var value:String;

  public function new(v:String) {
    value = v;
  }
}

class Main {
  static function mk(v:String):Box {
    return new Box(v);
  }

  static function main() {
    Sys.println(mk("ok").value);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmprunciobj/src" -main Main --hxhx-out "$tmprunciobj/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"
grep -q "HxAnon.get (Obj.repr (mk (\"ok\"))) \"value\"" "$tmprunciobj/out/Main.ml"


echo "== Stage3 regression: array concat/map/join chain lowers to bootstrap intrinsics"
tmpmapjoin="$tmpdir/array_map_join"
mkdir -p "$tmpmapjoin/src"
cat >"$tmpmapjoin/src/Main.hx" <<'HX'
class Main {
  static function mergeArgs(cmd:String, args:Array<String>) {
    return [cmd].concat(args).map(Std.string).join(" ");
  }

  static function main() {
    Sys.println(mergeArgs("haxe", ["-version"]));
  }
}
HX
out="$($HXHX_BIN --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run -cp "$tmpmapjoin/src" -main Main --hxhx-out "$tmpmapjoin/out")"
echo "$out" | grep -q "^stage3=ok$"
grep -q "HxBootArray.map_dyn" "$tmpmapjoin/out/Main.ml"
grep -q "HxBootArray.join_dyn" "$tmpmapjoin/out/Main.ml"

echo "== Stage3 regression: instance method callback references bind this in emitted OCaml"
tmpmethodcb="$tmpdir/instance_method_callback"
mkdir -p "$tmpmethodcb/src"
cat >"$tmpmethodcb/src/Main.hx" <<'HX'
class Main {
  public function new() {}

  function printField(v:String):String {
    return v;
  }

  function printStructure(fields:Array<String>):String {
    return fields.map(printField).join(",");
  }

  static function main() {
    var m = new Main();
    Sys.println(m.printStructure(["a", "b"]));
  }
}
HX
out="$($HXHX_BIN --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpmethodcb/src" -main Main --hxhx-out "$tmpmethodcb/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"
grep -q "printField (this_)" "$tmpmethodcb/out/Main.ml"

echo "== Stage3 regression: instance field roundtrip compiles and runs"
tmpinstfieldrun="$tmpdir/instance_field_run"
mkdir -p "$tmpinstfieldrun/src"
cat >"$tmpinstfieldrun/src/Main.hx" <<'HX'
class Main {
  var x:Int;

  public function new() {
    this.x = 41;
  }

  function ping():Int {
    return this.x;
  }

  static function main() {
    var m = new Main();
    Sys.println(Std.string(m.ping()));
  }
}
HX
out="$($HXHX_BIN --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpinstfieldrun/src" -main Main --hxhx-out "$tmpinstfieldrun/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^41$"
echo "$out" | grep -q "^run=ok$"
grep -q "HxAnon.set (Obj.repr __hx_obj)" "$tmpinstfieldrun/out/Main.ml"
grep -q "HxAnon.get (Obj.repr (this_))" "$tmpinstfieldrun/out/Main.ml"

echo "== Stage3 bring-up: imported sys.FileSystem + haxe.io.Path statics lower to runtime"
tmpfs="$tmpdir/filesystem_path"
mkdir -p "$tmpfs/src"
mkdir -p "$tmpfs/src/sys"
mkdir -p "$tmpfs/src/haxe/io"
cat >"$tmpfs/src/sys/FileSystem.hx" <<'HX'
package sys;

/**
 * Minimal extern stub used by `scripts/test-hxhx-targets.sh`.
 *
 * Why
 * - Stage3 bring-up needs to support upstream-ish code that imports `sys.FileSystem`
 *   and calls static helpers like `FileSystem.fullPath(...)`.
 *
 * What
 * - We intentionally declare this as `extern` so no OCaml implementation unit is emitted.
 *   The program only compiles if the Stage3 emitter rewrites `FileSystem.*` to our runtime
 *   module (`HxFileSystem.*`).
 */
extern class FileSystem {
  public static function fullPath(path:String):String;
}
HX
cat >"$tmpfs/src/haxe/io/Path.hx" <<'HX'
package haxe.io;

/**
 * Minimal extern stub used by `scripts/test-hxhx-targets.sh`.
 *
 * Why
 * - Mirrors upstream-ish usage patterns: `import haxe.io.Path; Path.join([...])`.
 *
 * What
 * - Declared as `extern` so no OCaml unit is emitted; compilation relies on the Stage3
 *   emitter rewriting `Path.join(...)` to a runtime implementation.
 */
extern class Path {
  public static function join(parts:Array<String>):String;
}
HX
cat >"$tmpfs/src/Main.hx" <<'HX'
import sys.FileSystem;
import haxe.io.Path;

class Main {
  static function main() {
    var here = FileSystem.fullPath(".");
    var unit = Path.join([here, "unit"]);
    Sys.println(unit);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpfs/src" -main Main --hxhx-out "$tmpfs/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "unit"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: body parse recovery doesn't truncate after unsupported constructs"
tmpbodyrecover="$tmpdir/body_recover"
mkdir -p "$tmpbodyrecover/src"
cat >"$tmpbodyrecover/src/Main.hx" <<'HX'
class Main {
  static function main() {
    trace("A");
    // Regression: `for` loops must parse and must not truncate the remainder of
    // the function body (we previously saw only A/C printed due to `SForIn` missing
    // from the bootstrap snapshot).
    for (i in 0...3) {
      trace(i);
    }
    trace("C");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpbodyrecover/src" -main Main --hxhx-out "$tmpbodyrecover/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^A$"
echo "$out" | grep -q "^0$"
echo "$out" | grep -q "^1$"
echo "$out" | grep -q "^2$"
echo "$out" | grep -q "^C$"
echo "$out" | grep -q "^run=ok$"

	echo "== Stage3 bring-up: parses try/catch expression initializer"
	tmptry="$tmpdir/try_expr"
	mkdir -p "$tmptry/src"
	cat >"$tmptry/src/Main.hx" <<'HX'
class Main {
  static function main() {
    // Gate2 regression: `try` is commonly used as an *expression* in variable initializers.
    // Stage3 should parse this shape without producing `EUnsupported("try")`.
    var x = try {
      1;
    } catch (e:Dynamic) {
      2;
    };
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit --std "$tmpdir/fake_std" -cp "$tmptry/src" -main Main --hxhx-out "$tmptry/out")"
echo "$out" | grep -q "^unsupported_exprs_total=0$"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Stage3 bring-up: try/catch statement body is not collapsed"
tmptrystmt="$tmpdir/try_stmt"
mkdir -p "$tmptrystmt/src"
cat >"$tmptrystmt/src/Main.hx" <<'HX'
class Main {
  static function main() {
    trace("A");
    try {
      trace("TRY");
    } catch (e:Dynamic) {
      trace("CATCH");
    }
    trace("C");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmptrystmt/src" -main Main --hxhx-out "$tmptrystmt/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^A$"
echo "$out" | grep -q "^TRY$"
echo "$out" | grep -q "^C$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: rest args pack into Array<T>"
tmprest="$tmpdir/rest_args"
mkdir -p "$tmprest/src"
cat >"$tmprest/src/Main.hx" <<'HX'
class Main {
  static function join(prefix:String, ...parts:String):String {
    // Upstream shape (RunCi config) uses `rest.toArray().join(...)`.
    return prefix + ":" + parts.toArray().join(",");
  }

  static function main() {
    trace(join("p"));
    trace(join("p", "a"));
    trace(join("p", "a", "b"));
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmprest/src" -main Main --hxhx-out "$tmprest/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^p:$"
echo "$out" | grep -q "^p:a$"
echo "$out" | grep -q "^p:a,b$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: rest-only args (no fixed params) pack into Array<T>"
tmprestonly="$tmpdir/rest_only_args"
mkdir -p "$tmprestonly/src"
cat >"$tmprestonly/src/Main.hx" <<'HX'
class Main {
  static function join(...parts:String):String {
    // Upstream `runci.Config.getMiscSubDir(...subDir)` is a rest-only signature.
    // Ensure our frontend+emitter preserve the rest marker even when there are
    // no fixed parameters.
    return "[" + parts.toArray().join(",") + "]";
  }

  static function main() {
    trace(join());
    trace(join("a"));
    trace(join("a", "b"));
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmprestonly/src" -main Main --hxhx-out "$tmprestonly/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^\\[\\]$"
echo "$out" | grep -q "^\\[a\\]$"
echo "$out" | grep -q "^\\[a,b\\]$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: string ternary in println emits"
tmpternary="$tmpdir/ternary_print"
mkdir -p "$tmpternary/src"
cat >"$tmpternary/src/Main.hx" <<'HX'
class Main {
  static function main() {
    var colorSupported = true;
    var msg = "hello";
    Sys.println(colorSupported ? ">" + msg + "<" : msg);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpternary/src" -main Main --hxhx-out "$tmpternary/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^>hello<$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: string interpolation + hex escapes"
tmpstr="$tmpdir/string_interp"
mkdir -p "$tmpstr/src"
cat >"$tmpstr/src/Main.hx" <<'HX'
class Main {
  static function main() {
    var x = 3;
    Sys.println('x=$x');
    Sys.println('y=${x}');
    Sys.println("hex=\x41");
    Sys.println("dollar=$$");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpstr/src" -main Main --hxhx-out "$tmpstr/out")"
echo "$out" | grep -q "^x=3$"
echo "$out" | grep -q "^y=3$"
echo "$out" | grep -q "^hex=A$"
echo "$out" | grep -Fxq "dollar=\$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: package type paths lower to OCaml modules"
tmppkg="$tmpdir/pkg_module"
mkdir -p "$tmppkg/src/a/b"
cat >"$tmppkg/src/a/b/Util.hx" <<'HX'
package a.b;

class Util {
  public static function hello():String {
    return "hi";
  }
}
HX
cat >"$tmppkg/src/Main.hx" <<'HX'
import a.b.Util;

class Main {
  static function main() {
    var s = a.b.Util.hello();
    untyped __ocaml__("print_endline s");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmppkg/src" -main Main --hxhx-out "$tmppkg/out")"
echo "$out" | grep -q "^hi$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: parent package type name resolves"
tmppkg_parent="$tmpdir/pkg_parent_type"
mkdir -p "$tmppkg_parent/src/a/b"
cat >"$tmppkg_parent/src/a/Util.hx" <<'HX'
package a;

class Util {
  public static function hello():String {
    return "hi-parent";
  }
}
HX
cat >"$tmppkg_parent/src/a/b/Main.hx" <<'HX'
package a.b;

class Main {
  static function main() {
    // Upstream shape: refer to a type in the parent package without an explicit import.
    var s = Util.hello();
    untyped __ocaml__("print_endline s");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmppkg_parent/src" -main a.b.Main --hxhx-out "$tmppkg_parent/out")"
echo "$out" | grep -q "^hi-parent$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: optional args can be skipped by type (runci install git)"
tmpopt="$tmpdir/optional_arg_shift"
mkdir -p "$tmpopt/src/runci/targets"
cat >"$tmpopt/src/runci/System.hx" <<'HX'
package runci;

class System {
  static public function haxelibInstallGit(account:String, repository:String, ?branch:String, ?srcPath:String, useRetry:Bool = false, ?altName:String):Void {
    Sys.println(useRetry ? "retry" : "noretry");
  }
}
HX
cat >"$tmpopt/src/runci/targets/Main.hx" <<'HX'
package runci.targets;

import runci.System.*;

class Main {
  static function main() {
    // Upstream shape: pass the later Bool arg while omitting optional String args.
    haxelibInstallGit("HaxeFoundation", "hxjava", true);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpopt/src" -main runci.targets.Main --hxhx-out "$tmpopt/out")"
echo "$out" | grep -q "^retry$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: sys.io.File whole-file ops map to runtime"
tmpfileops="$tmpdir/sys_io_file_ops"
mkdir -p "$tmpfileops/src"
mkdir -p "$tmpfileops/src/sys/io"
cat >"$tmpfileops/src/sys/io/File.hx" <<'HX'
package sys.io;

// Minimal stub so Stage3 can resolve `import sys.io.File` in bring-up tests.
//
// The Stage3 emitter treats whole-file operations as intrinsics and rewrites call sites to
// the OCaml runtime (`HxFile.*`), so these bodies are not meant to be executed.
class File {
  public static function getContent(path:String):String return "";
  public static function saveContent(path:String, content:String):Void {}
}
HX
cat >"$tmpfileops/src/Main.hx" <<HX
import sys.io.File;

class Main {
  static function main() {
    File.saveContent("${tmpfileops}/hello.txt", "hi");
    Sys.println(File.getContent("${tmpfileops}/hello.txt"));
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpfileops/src" -main Main --hxhx-out "$tmpfileops/out")"
echo "$out" | grep -q "^hi$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: Xml.parse collapses to bring-up poison (compile-only)"
tmpxml="$tmpdir/xml_parse_poison"
mkdir -p "$tmpxml/src"
cat >"$tmpxml/src/Main.hx" <<'HX'
class Main {
  static function main() {
    var x = Xml.parse("<a/>");
    Sys.println("ok");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpxml/src" -main Main --hxhx-out "$tmpxml/out")"
echo "$out" | grep -q "^ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 regression: Xml.createElement camelCase constructor mapping links"
tmpxmlctor="$tmpdir/xml_create_element"
mkdir -p "$tmpxmlctor/src"
cat >"$tmpxmlctor/src/Main.hx" <<'HX'
class Main {
  static function main() {
    var xml = Xml.createElement("node");
    Sys.println(xml.nodeName);
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run -cp "$tmpxmlctor/src" -main Main --hxhx-out "$tmpxmlctor/out")"
echo "$out" | grep -q "^stage3=ok$"

echo "== Stage3 regression: unary minus on php.Const.INF lowers to a float-safe form"
tmpphpinf="$tmpdir/php_const_inf_unary"
mkdir -p "$tmpphpinf/src/php"
cat >"$tmpphpinf/src/php/Const.hx" <<'HX'
package php;

class Const {
  public static var INF:Float = 0.;
  public static var NAN:Float = 0.;
}
HX
cat >"$tmpphpinf/src/Main.hx" <<'HX'
import php.Const;

class Main {
  static function main() {
    var x = -Const.INF;
    if (Math.isNaN(x)) {
      Sys.println("nan");
    } else {
      Sys.println(Std.string(x));
    }
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run -cp "$tmpphpinf/src" -main Main --hxhx-out "$tmpphpinf/out")"
echo "$out" | grep -q "^stage3=ok$"
test -f "$tmpphpinf/out/Main.ml"
grep -Eq "neg_infinity|\\(-\\.(Php_Const.iNF)\\)" "$tmpphpinf/out/Main.ml"

echo "== Stage3 bring-up: multi-unit .hxml via --next"
tmpmulti="$tmpdir/multi_unit_hxml"
mkdir -p "$tmpmulti/src"
cat >"$tmpmulti/src/A.hx" <<'HX'
class A {
  static function main() {
    Sys.println("A");
  }
}
HX
cat >"$tmpmulti/src/B.hx" <<'HX'
class B {
  static function main() {
    Sys.println("B");
  }
}
HX
cat >"$tmpmulti/build.hxml" <<HX
-cp $tmpmulti/src
-main A
--next
-cp $tmpmulti/src
-main B
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-out "$tmpmulti/out" "$tmpmulti/build.hxml")"
test "$(echo "$out" | grep -c '^stage3=ok$')" -eq 2
echo "$out" | grep -q "^A$"
echo "$out" | grep -q "^B$"

echo "== Stage3 bring-up: multi-unit .hxml via --each (common prefix)"
tmpeach="$tmpdir/each_unit_hxml"
mkdir -p "$tmpeach/src"
cat >"$tmpeach/src/A.hx" <<'HX'
class A { static function main() {} }
HX
cat >"$tmpeach/src/B.hx" <<'HX'
class B { static function main() {} }
HX
cat >"$tmpeach/common.hxml" <<HX
-cp $tmpeach/src
HX
cat >"$tmpeach/build.hxml" <<HX
$tmpeach/common.hxml

--each

-main A

--next

-main B
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-type-only --hxhx-out "$tmpeach/out" "$tmpeach/build.hxml")"
test "$(echo "$out" | grep -c '^stage3=type_only_ok$')" -eq 2

echo "== Stage3 bring-up: cmd-only unit is skipped (-cmd)"
tmpcmd="$tmpdir/cmd_only_unit_hxml"
mkdir -p "$tmpcmd/src"
cat >"$tmpcmd/src/Main.hx" <<'HX'
class Main { static function main() {} }
HX
cat >"$tmpcmd/build.hxml" <<HX
-cmd echo Hello from cmd-only unit
--next
-cp $tmpcmd/src
-main Main
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-type-only "$tmpcmd/build.hxml")"
test "$(echo "$out" | grep -c '^stage3=skipped_cmd_only$')" -eq 1
test "$(echo "$out" | grep -c '^stage3=type_only_ok$')" -eq 1

echo "== Stage3 bring-up: lazy type-driven module loading (same-package type)"
tmplazy="$tmpdir/lazy_module_loading"
mkdir -p "$tmplazy/src/p"
cat >"$tmplazy/src/p/Main.hx" <<'HX'
package p;

class Main {
  static function main() {
    // No `import p.Util;` here. In real Haxe this resolves via same-package lookup.
    Util.ping();
  }
}
HX
cat >"$tmplazy/src/p/Util.hx" <<'HX'
package p;

class Util {
  public static function ping() {
    Sys.println("lazy=ok");
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmplazy/src" -main p.Main --hxhx-out "$tmplazy/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^lazy=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 regression: lazy type loading in root package"
tmprootlazy="$tmpdir/lazy_module_loading_root_pkg"
mkdir -p "$tmprootlazy/src"
cat >"$tmprootlazy/src/Main.hx" <<'HX'
class Main {
  static function main() {
    // No import for Macro. In root package, this must still resolve to Macro.hx.
    Sys.println(Std.string(Macro.ping()));
  }
}
HX
cat >"$tmprootlazy/src/Macro.hx" <<'HX'
class Macro {
  public static function ping():Int {
    return 7;
  }
}
HX
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmprootlazy/src" -main Main --hxhx-out "$tmprootlazy/out")"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^7$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: type-only checks full graph"
type_only_out="$tmpdir/out_stage3_type_only"
out="$("$HXHX_BIN" --hxhx-stage3 --hxhx-type-only -cp "$ROOT/workloads/hih-compiler/fixtures/src" -main demo.A --hxhx-out "$type_only_out")"
echo "$out" | grep -q "^resolved_modules="
echo "$out" | grep -q "^typed_modules="
echo "$out" | grep -q "^header_only_modules=0$"
echo "$out" | grep -q "^parsed_methods_total=12$"
echo "$out" | grep -q "^stage3=type_only_ok$"
test ! -f "$type_only_out/out.exe"

echo "== Stage3 bring-up: runs --macro via macro host (allowlist)"
stage3_out2="$tmpdir/out_stage3_macro"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/workloads/hih-compiler/fixtures/src" -main demo.A -D HXHX_FLAG=ok --macro 'BuiltinMacros.readFlag()' --macro 'BuiltinMacros.smoke()' --macro 'BuiltinMacros.genModule()' --macro 'BuiltinMacros.dumpDefines()' --macro 'BuiltinMacros.registerHooks()' --hxhx-out "$stage3_out2")"
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
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/workloads/hih-compiler/fixtures/src" -main demo.A -D HXHX_FLAG=ok --macro 'hxhxmacros.ExternalMacros.external()' --hxhx-out "$stage3_out3")"
echo "$out" | grep -q "^macro_run\\[0\\]=external=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_EXTERNAL\\]=1$"
echo "$out" | grep -q "^stage3=ok$"
test -f "$stage3_out3/HxHxExternal.ml"
grep -q 'external_flag' "$stage3_out3/HxHxExternal.ml"

echo "== Stage3 bring-up: upstream-ish Macro.init() compiles + runs (haxe.macro.Context override)"
stage3_out4="$tmpdir/out_stage3_upstream_macro"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/workloads/hih-compiler/fixtures/src" -cp "$ROOT/examples/hxhx-macros/src" -main demo.A --macro 'Macro.init()' --hxhx-out "$stage3_out4")"
echo "$out" | grep -q "^macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^hook_onGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^stage3=ok$"

echo "== Stage3 bring-up: runs a non-builtin macro entrypoint with a String arg"
stage3_out5="$tmpdir/out_stage3_arg_macro"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 -cp "$ROOT/workloads/hih-compiler/fixtures/src" -cp "$ROOT/examples/hxhx-macros/src" -main demo.A --macro 'hxhxmacros.ArgsMacros.setArg("ok")' --hxhx-out "$stage3_out5")"
echo "$out" | grep -q "^macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_ARG\\]=ok$"
echo "$out" | grep -q "^stage3=ok$"

echo "== Stage4 bring-up: fixture plugin exercises defines + classpath injection + hook emission"
tmpplugin="$tmpdir/plugin_fixture"
mkdir -p "$tmpplugin/src"
mkdir -p "$tmpplugin/plugin_cp"
cat >"$tmpplugin/src/Main.hx" <<'HX'
import AddedFromPlugin;

class Main {
  static function main() {
    AddedFromPlugin.ping();
    Sys.println("main=ok");
  }
}
HX
cat >"$tmpplugin/plugin_cp/AddedFromPlugin.hx" <<'HX'
class AddedFromPlugin {
  public static function ping() {
    Sys.println("plugin_cp=ok");
  }
}
HX
plugin_out="$tmpplugin/out"
out="$(
  HXHX_PLUGIN_FIXTURE_CP="$tmpplugin/plugin_cp" \
  HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" \
  "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies \
    -cp "$tmpplugin/src" \
    -cp "$ROOT/examples/hxhx-macros/src" \
    -main Main \
    --macro 'hxhxmacros.PluginFixtureMacros.init()' \
    --hxhx-out "$plugin_out"
)"
echo "$out" | grep -q "^macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_PLUGIN_FIXTURE\\]=1$"
echo "$out" | grep -q "^hook_afterTyping\\[0\\]=ok$"
echo "$out" | grep -q "^hook_onGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^stage3=ok$"
test -f "$plugin_out/HxHxPluginFixtureGen.ml"
echo "$out" | grep -q "^plugin_cp=ok$"
echo "$out" | grep -q "^main=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage4 bring-up: fixture plugin works with --library reflaxe.ocaml (haxelib resolution)"
tmpplugin_lib="$tmpdir/plugin_fixture_lib"
mkdir -p "$tmpplugin_lib/src"
mkdir -p "$tmpplugin_lib/plugin_cp"
cat >"$tmpplugin_lib/src/Main.hx" <<'HX'
import AddedFromPlugin;

class Main {
  static function main() {
    AddedFromPlugin.ping();
    Sys.println("main=ok");
  }
}
HX
cat >"$tmpplugin_lib/plugin_cp/AddedFromPlugin.hx" <<'HX'
class AddedFromPlugin {
  public static function ping() {
    Sys.println("plugin_cp=ok");
  }
}
HX
plugin_out_lib="$tmpplugin_lib/out"
out="$(
  HXHX_PLUGIN_FIXTURE_CP="$tmpplugin_lib/plugin_cp" \
  HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" \
  "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies \
    -cp "$tmpplugin_lib/src" \
    -cp "$ROOT/examples/hxhx-macros/src" \
    --library reflaxe.ocaml \
    -main Main \
    --macro 'hxhxmacros.PluginFixtureMacros.init()' \
    --hxhx-out "$plugin_out_lib"
)"
echo "$out" | grep -q "^macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_PLUGIN_FIXTURE\\]=1$"
echo "$out" | grep -q "^hook_afterTyping\\[0\\]=ok$"
echo "$out" | grep -q "^hook_onGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^stage3=ok$"
test -f "$plugin_out_lib/HxHxPluginFixtureGen.ml"
echo "$out" | grep -q "^plugin_cp=ok$"
echo "$out" | grep -q "^main=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: ingests haxelib -D defines (haxe_libraries/*.hxml)"
tmpmini="$tmpdir/haxelib_define_fixture"
mini_src="$tmpmini/src"
mkdir -p "$mini_src"

# Lix-managed projects encode `haxelib path` output under `haxe_libraries/<lib>.hxml`.
# Stage3 resolves that file directly (no process spawn) when present.
mini_hxml="$ROOT/haxe_libraries/hxhx_mini_lib.hxml"
cat >"$mini_hxml" <<'HXML'
# Internal test fixture for Stage3 `--library` resolution.
-D hxhx_mini=1
--macro hxhxmacros.HaxelibInitMacros.init()
HXML

cat >"$mini_src/Ok.hx" <<'HX'
class Ok {}
HX
cat >"$mini_src/Main.hx" <<'HX'
#if hxhx_mini
import Ok;
#else
import DoesNotExist;
#end

class Main {
  static function main() {}
}
HX
mini_out="$tmpmini/out"
out="$(
  HXHX_RUN_HAXELIB_MACROS=1 \
  HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" \
  "$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit \
    -cp "$mini_src" \
    --library hxhx_mini_lib \
    -main Main \
    --hxhx-out "$mini_out"
)"
echo "$out" | grep -q "^lib_macro_run\\[0\\]=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_HAXELIB_INIT\\]=1$"
echo "$out" | grep -q "^hook_afterTyping\\[0\\]=ok$"
echo "$out" | grep -q "^hook_onGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^hook_afterGenerate\\[0\\]=ok$"
echo "$out" | grep -q "^macro_define2\\[HXHX_HAXELIB_INIT_AFTER_TYPING\\]=1$"
echo "$out" | grep -q "^macro_define2\\[HXHX_HAXELIB_INIT_ON_GENERATE\\]=1$"
echo "$out" | grep -q "^macro_define2\\[HXHX_HAXELIB_INIT_AFTER_GENERATE\\]=1$"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Stage3 bring-up: expression macro expansion replaces call sites"
tmpexpr="$tmpdir/expr_macro"
mkdir -p "$tmpexpr/src"
cat >"$tmpexpr/src/Main.hx" <<'HX'
import hxhxmacros.ExprMacroShim;

class Main {
  static function main() {
    trace(ExprMacroShim.hello());
  }
}
HX
out="$(HXHX_EXPR_MACROS='hxhxmacros.ExprMacroShim.hello()' HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpexpr/src" -cp "$ROOT/examples/hxhx-macros/src" -main Main --hxhx-out "$tmpexpr/out")"
echo "$out" | grep -q "^expr_macros_expanded=1$"
echo "$out" | grep -q "^HELLO$"
echo "$out" | grep -q "^run=ok$"

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

out="$(HXHX_ADD_CP="$tmpcp/extra" HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 -cp "$tmpcp/src" -main Main --macro 'BuiltinMacros.addCpFromEnv()' --hxhx-out "$tmpcp/out_with_cp")"
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

out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 -cp "$tmpgen/src" -main Main --macro 'BuiltinMacros.genHxModule()' --hxhx-out "$tmpgen/out_with_macro")"
echo "$out" | grep -q "^macro_run\\[0\\]=genHx=ok$"
echo "$out" | grep -q "^macro_define\\[HXHX_HXGEN\\]=1$"
echo "$out" | grep -q "^stage3=ok$"
test -f "$tmpgen/out_with_macro/_gen_hx/Gen.hx"

echo "== Stage3 bring-up: include(\"Mod\") adds resolver roots"
tmpinc="$tmpdir/include_test"
mkdir -p "$tmpinc/src"
cat >"$tmpinc/src/Main.hx" <<'HX'
class Main {
  static function main() {
    return 0;
  }
}
HX
cat >"$tmpinc/src/Extra.hx" <<'HX'
class Extra {}
HX
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 --hxhx-no-emit -cp "$tmpinc/src" -main Main --macro 'include("Extra")' --hxhx-out "$tmpinc/out")"
echo "$out" | grep -q "^macro_run\\[0\\]=include=ok$"
echo "$out" | grep -q "^resolved_modules=2$"
echo "$out" | grep -q "^stage3=no_emit_ok$"

echo "== Stage3 bring-up: @:build emits a field into the typed program"
tmpbuild="$tmpdir/build_fields_test"
mkdir -p "$tmpbuild/src"
cat >"$tmpbuild/src/Main.hx" <<'HX'
@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())
class Main {
  static function main() {
    generated();
  }
}
HX
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpbuild/src" -cp "$ROOT/examples/hxhx-macros/src" -main Main --hxhx-out "$tmpbuild/out")"
echo "$out" | grep -q "^build_macro\\[Main\\]\\[0\\]=hxhxmacros.BuildFieldMacros.addGeneratedField()$"
echo "$out" | grep -q "^build_macro_run\\[Main\\]\\[0\\]=ok$"
echo "$out" | grep -q "^build_fields\\[Main\\]=1$"
echo "$out" | grep -q "^from_hxhx_build_macro$"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: @:build return Array<Field> emits delta members"
tmpbuild_ret="$tmpdir/build_fields_return_test"
mkdir -p "$tmpbuild_ret/src"
cat >"$tmpbuild_ret/src/Main.hx" <<'HX'
@:build(hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn())
class Main {
  static function main() {
    generated_return();
  }
}
HX
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpbuild_ret/src" -cp "$ROOT/examples/hxhx-macros/src" -main Main --hxhx-out "$tmpbuild_ret/out")"
echo "$out" | grep -q "^build_macro\\[Main\\]\\[0\\]=hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()$"
echo "$out" | grep -q "^build_macro_run\\[Main\\]\\[0\\]=ok$"
echo "$out" | grep -q "^build_fields\\[Main\\]=1$"
echo "$out" | grep -q "^from_hxhx_build_macro_return$"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: @:build return Array<Field> replaces existing member by name"
tmpbuild_rep="$tmpdir/build_fields_replace_test"
mkdir -p "$tmpbuild_rep/src"
cat >"$tmpbuild_rep/src/Main.hx" <<'HX'
@:build(hxhxmacros.ReturnFieldMacros.replaceGeneratedFieldReturn())
class Main {
  public static function generated_replace():Void {
    trace("ORIG");
  }

  static function main() {
    generated_replace();
  }
}
HX
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpbuild_rep/src" -cp "$ROOT/examples/hxhx-macros/src" -main Main --hxhx-out "$tmpbuild_rep/out")"
echo "$out" | grep -q "^build_macro\\[Main\\]\\[0\\]=hxhxmacros.ReturnFieldMacros.replaceGeneratedFieldReturn()$"
echo "$out" | grep -q "^build_macro_run\\[Main\\]\\[0\\]=ok$"
echo "$out" | grep -q "^build_fields\\[Main\\]=1$"
echo "$out" | grep -q "^from_hxhx_build_macro_replaced$"
echo "$out" | grep -vq "^ORIG$"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage3 bring-up: Array<Field> printer supports args + var"
tmpbuild_print="$tmpdir/build_fields_printer_test"
mkdir -p "$tmpbuild_print/src"
cat >"$tmpbuild_print/src/Main.hx" <<'HX'
@:build(hxhxmacros.FieldPrinterMacros.addArgFunctionAndVar())
class Main {
  static function main() {
    generated_with_args(1, 2);
  }
}
HX
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-stage3 --hxhx-emit-full-bodies -cp "$tmpbuild_print/src" -cp "$ROOT/examples/hxhx-macros/src" -main Main --hxhx-out "$tmpbuild_print/out")"
echo "$out" | grep -q "^build_macro\\[Main\\]\\[0\\]=hxhxmacros.FieldPrinterMacros.addArgFunctionAndVar()$"
echo "$out" | grep -q "^build_macro_run\\[Main\\]\\[0\\]=ok$"
echo "$out" | grep -q "^build_fields\\[Main\\]=1$"
echo "$out" | grep -q "^from_hxhx_field_printer$"
echo "$out" | grep -q "^stage3=ok$"
echo "$out" | grep -q "^run=ok$"

echo "== Stage4 bring-up: macro host RPC handshake + stub Context/Compiler calls"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-macro-selftest)"
echo "$out" | grep -q "^macro_host=ok$"
echo "$out" | grep -q "^macro_ping=pong$"
echo "$out" | grep -q "^macro_define=ok$"
echo "$out" | grep -q "^macro_defined=yes$"
echo "$out" | grep -q "^macro_definedValue=bar$"

echo "== Stage4 bring-up: duplex define roundtrip via macro.run"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-macro-run 'BuiltinMacros.smoke()')"
echo "$out" | grep -q "^macro_run=smoke:type=builtin:String;define=yes$"

echo "== Stage4 bring-up: macro.run builtin entrypoint"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-macro-run "hxhxmacrohost.BuiltinMacros.smoke()")"
echo "$out" | grep -q "^macro_run=smoke:type=builtin:String;define=yes$"
echo "$out" | grep -q "^OK hxhx macro run$"

echo "== Stage4 bring-up: macro.run errors include position payload"
set +e
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-macro-run "hxhxmacrohost.BuiltinMacros.fail()" 2>&1)"
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "Expected macro.run failure, but command succeeded." >&2
  exit 1
fi
echo "$out" | grep -q "BuiltinMacros.hx:"

echo "== Stage4 bring-up: context.getType stub"
out="$(HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_STABLE" "$HXHX_BIN" --hxhx-macro-get-type String)"
echo "$out" | grep -q "^macro_getType=builtin:String$"
echo "$out" | grep -q "^OK hxhx macro getType$"

echo "OK: hxhx target presets"
