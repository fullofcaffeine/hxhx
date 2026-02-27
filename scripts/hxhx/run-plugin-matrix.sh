#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STRICT="${HXHX_PLUGIN_MATRIX_STRICT:-1}"
ALLOW_SKIP="${HXHX_PLUGIN_MATRIX_ALLOW_SKIP:-0}"
CORO_DIR="${HXHX_PLUGIN_CORO_DIR:-}"
HXHX_BIN_RESOLVED="${HXHX_BIN:-}"
HXHX_MACRO_HOST_BIN="${HXHX_MACRO_HOST_EXE:-}"
export HXHX_BIN_RESOLVED
export HXHX_MACRO_HOST_BIN

for value_name in STRICT ALLOW_SKIP; do
  eval "value=\${$value_name}"
  case "$value" in
    0|1) ;;
    *)
      echo "Invalid $value_name=$value (expected 0 or 1)." >&2
      exit 2
      ;;
  esac
done

summary=()
failures=0

run_check() {
  local name="$1"
  local marker="$2"
  local cmd="$3"
  local required="${4:-1}"
  local start end elapsed code

  start="$(date +%s)"
  echo ""
  echo "== Plugin matrix check: $name"
  echo "== command: $cmd"

  set +e
  bash -lc "$cmd"
  code="$?"
  set -e

  end="$(date +%s)"
  elapsed="$((end - start))"

  if [ "$code" -eq 0 ]; then
    summary+=("$name: PASS (${elapsed}s)")
    echo "${marker}:PASS"
    return 0
  fi

  if [ "$required" = "0" ] || [ "$ALLOW_SKIP" = "1" ]; then
    summary+=("$name: SKIP (${elapsed}s, exit=$code)")
    echo "${marker}:SKIP"
    return 0
  fi

  summary+=("$name: FAIL (${elapsed}s, exit=$code)")
  echo "${marker}:FAIL"
  failures=1
  return "$code"
}

tmpdir="$(mktemp -d)"
mini_lib_hxml="$ROOT/haxe_libraries/hxhx_plugin_matrix_lib.hxml"
cleanup() {
  rm -f "$mini_lib_hxml"
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cat >"$tmpdir/EvalVmPluginSmoke.hx" <<'HX'
import haxe.macro.Context;
import haxe.macro.Expr;

class EvalVmPluginSmoke {
	public static macro function status():ExprOf<String> {
		var marker = "evalvm_define_missing";
		if (Context.defined("eval")) {
			final pluginLoader = eval.vm.Context.loadPlugin;
			if (pluginLoader != null) {
				marker = "evalvm_api_available";
			}
		}
		return macro $v{marker};
	}
}
HX

cat >"$tmpdir/EvalVmMain.hx" <<'HX'
class EvalVmMain {
	static function main() {
		Sys.println(EvalVmPluginSmoke.status());
	}
}
HX

plugin_tmp="$tmpdir/plugin_stage3"
mkdir -p "$plugin_tmp/src"
mkdir -p "$plugin_tmp/plugin_cp"
cat >"$plugin_tmp/src/Main.hx" <<'HX'
import AddedFromPlugin;

class Main {
	static function main() {
		AddedFromPlugin.ping();
		Sys.println("plugin_main=ok");
	}
}
HX

cat >"$plugin_tmp/plugin_cp/AddedFromPlugin.hx" <<'HX'
class AddedFromPlugin {
	public static function ping() {
		Sys.println("plugin_cp=ok");
	}
}
HX

run_check \
  "reflaxe.ocaml macro build fixture" \
  "PLUGIN_REFLAXE_OCAML" \
  "cd '$ROOT/packages/reflaxe.ocaml/examples/build-macro' && haxe build.hxml"

run_check \
  "native backend plugin build smoke (.cmxs + manifest)" \
  "PLUGIN_NATIVE_BUILD" \
  "cd '$ROOT' && npm run -s test:hxhx:native-plugin-build-smoke"

run_check \
  "eval.vm plugin API smoke" \
  "PLUGIN_EVAL_VM" \
  "out=\"\$(haxe -cp '$tmpdir' -main EvalVmMain --interp 2>&1)\" && printf '%s\n' \"\$out\" && printf '%s\n' \"\$out\" | grep -q '^evalvm_api_available$'"

cat >"$mini_lib_hxml" <<'HXML'
# Internal plugin-matrix fixture for Stage3 --library macro activation.
-D hxhx_plugin_matrix_lib=1
--macro hxhxmacros.HaxelibInitMacros.init()
HXML

mini_tmp="$tmpdir/haxelib_macro_lib"
mkdir -p "$mini_tmp/src"
cat >"$mini_tmp/src/Ok.hx" <<'HX'
class Ok {}
HX
cat >"$mini_tmp/src/Main.hx" <<'HX'
#if hxhx_plugin_matrix_lib
import Ok;
#else
import MissingFromPluginMatrix;
#end

class Main {
	static function main() {}
}
HX

run_check \
  "hxhx stage3 library macro activation (--library + haxe_libraries/*.hxml)" \
  "PLUGIN_LIBRARY_MACRO" \
  "cd '$ROOT' && HXHX_BIN_STAGE3=\"\${HXHX_BIN_RESOLVED:-}\" && if [ -z \"\$HXHX_BIN_STAGE3\" ] || [ ! -x \"\$HXHX_BIN_STAGE3\" ]; then HXHX_BIN_STAGE3=\"\$(bash '$ROOT/scripts/hxhx/build-hxhx.sh' | tail -n 1)\"; fi && HXHX_MACRO_HOST_STAGE3=\"\${HXHX_MACRO_HOST_BIN:-}\" && if [ -z \"\$HXHX_MACRO_HOST_STAGE3\" ] || [ ! -x \"\$HXHX_MACRO_HOST_STAGE3\" ]; then HXHX_MACRO_HOST_STAGE3=\"\$(bash '$ROOT/scripts/hxhx/build-hxhx-macro-host.sh' | tail -n 1)\"; fi && test -x \"\$HXHX_BIN_STAGE3\" && test -x \"\$HXHX_MACRO_HOST_STAGE3\" && out=\"\$(OCAMLOPT='$ROOT/scripts/hxhx/ocamlopt-with-threads.sh' HXHX_RUN_HAXELIB_MACROS=1 HXHX_MACRO_HOST_EXE=\"\$HXHX_MACRO_HOST_STAGE3\" \"\$HXHX_BIN_STAGE3\" --hxhx-stage3 --hxhx-no-emit -cp '$mini_tmp/src' -cp '$ROOT/test/fixtures/hxhx-macros/src' --library hxhx_plugin_matrix_lib -main Main --hxhx-out '$mini_tmp/out' 2>&1)\" && printf '%s\n' \"\$out\" && printf '%s\n' \"\$out\" | grep -q '^lib_macro_run\\[0\\]=ok$' && printf '%s\n' \"\$out\" | grep -q '^macro_define\\[HXHX_HAXELIB_INIT\\]=1$' && printf '%s\n' \"\$out\" | grep -q '^hook_afterTyping\\[0\\]=ok$' && printf '%s\n' \"\$out\" | grep -q '^hook_onGenerate\\[0\\]=ok$' && printf '%s\n' \"\$out\" | grep -q '^hook_afterGenerate\\[0\\]=ok$' && printf '%s\n' \"\$out\" | grep -q '^macro_define2\\[HXHX_HAXELIB_INIT_AFTER_TYPING\\]=1$' && printf '%s\n' \"\$out\" | grep -q '^macro_define2\\[HXHX_HAXELIB_INIT_ON_GENERATE\\]=1$' && printf '%s\n' \"\$out\" | grep -q '^macro_define2\\[HXHX_HAXELIB_INIT_AFTER_GENERATE\\]=1$' && printf '%s\n' \"\$out\" | grep -q '^stage3=no_emit_ok$'"

run_check \
  "hxhx stage3 plugin fixture (hooks + classpath + --library activation)" \
  "PLUGIN_HXHX_STAGE3" \
  "cd '$ROOT' && HXHX_BIN_STAGE3=\"\${HXHX_BIN_RESOLVED:-}\" && if [ -z \"\$HXHX_BIN_STAGE3\" ] || [ ! -x \"\$HXHX_BIN_STAGE3\" ]; then HXHX_BIN_STAGE3=\"\$(bash '$ROOT/scripts/hxhx/build-hxhx.sh' | tail -n 1)\"; fi && HXHX_MACRO_HOST_STAGE3=\"\${HXHX_MACRO_HOST_BIN:-}\" && if [ -z \"\$HXHX_MACRO_HOST_STAGE3\" ] || [ ! -x \"\$HXHX_MACRO_HOST_STAGE3\" ]; then HXHX_MACRO_HOST_STAGE3=\"\$(bash '$ROOT/scripts/hxhx/build-hxhx-macro-host.sh' | tail -n 1)\"; fi && test -x \"\$HXHX_BIN_STAGE3\" && test -x \"\$HXHX_MACRO_HOST_STAGE3\" && out=\"\$(OCAMLOPT='$ROOT/scripts/hxhx/ocamlopt-with-threads.sh' HXHX_PLUGIN_FIXTURE_CP='$plugin_tmp/plugin_cp' HXHX_MACRO_HOST_EXE=\"\$HXHX_MACRO_HOST_STAGE3\" \"\$HXHX_BIN_STAGE3\" --hxhx-stage3 --hxhx-emit-full-bodies -cp '$plugin_tmp/src' -cp '$ROOT/test/fixtures/hxhx-macros/src' --library reflaxe.ocaml -main Main --macro 'hxhxmacros.PluginFixtureMacros.init()' --hxhx-out '$plugin_tmp/out' 2>&1)\" && printf '%s\n' \"\$out\" && printf '%s\n' \"\$out\" | grep -q '^macro_run\\[0\\]=ok$' && printf '%s\n' \"\$out\" | grep -q '^macro_define\\[HXHX_PLUGIN_FIXTURE\\]=1$' && printf '%s\n' \"\$out\" | grep -q '^hook_afterTyping\\[0\\]=ok$' && printf '%s\n' \"\$out\" | grep -q '^hook_onGenerate\\[0\\]=ok$' && printf '%s\n' \"\$out\" | grep -q '^stage3=ok$' && test -f '$plugin_tmp/out/HxHxPluginFixtureGen.ml' && printf '%s\n' \"\$out\" | grep -q '^plugin_cp=ok$' && printf '%s\n' \"\$out\" | grep -q '^plugin_main=ok$' && printf '%s\n' \"\$out\" | grep -q '^run=ok$'"

run_check \
  "hxhx native backend plugin runtime load smoke (ocaml dynlink manifest + negatives)" \
  "PLUGIN_NATIVE_RUNTIME" \
  "cd '$ROOT' && HXHX_BIN_STAGE3=\"\${HXHX_BIN_RESOLVED:-}\" && if [ -z \"\$HXHX_BIN_STAGE3\" ] || [ ! -x \"\$HXHX_BIN_STAGE3\" ]; then HXHX_BIN_STAGE3=\"\$(bash '$ROOT/scripts/hxhx/build-hxhx.sh' | tail -n 1)\"; fi && test -x \"\$HXHX_BIN_STAGE3\" && HXHX_BIN=\"\$HXHX_BIN_STAGE3\" HXHX_NATIVE_PLUGIN_RUNTIME_STAGE0_BUILD=0 OCAMLOPT='$ROOT/scripts/hxhx/ocamlopt-with-threads.sh' npm run -s test:hxhx:native-plugin-runtime-smoke"

if [ -n "$CORO_DIR" ]; then
  run_check \
    "coro plugin compatibility (optional external oracle)" \
    "PLUGIN_CORO" \
    "test -d '$CORO_DIR' && test -f '$CORO_DIR/tests.hxml' && test -f '$CORO_DIR/extraParams.hxml' && cd '$CORO_DIR' && haxe tests.hxml"
else
  run_check \
    "coro plugin compatibility (optional external oracle)" \
    "PLUGIN_CORO" \
    "echo 'Set HXHX_PLUGIN_CORO_DIR to run Coro compatibility checks.' >&2; exit 2" \
    "0"
fi

echo ""
echo "== Plugin matrix summary"
for line in "${summary[@]}"; do
  echo "$line"
done

if [ "$failures" -ne 0 ]; then
  echo "PLUGIN_MATRIX:FAIL"
  exit 1
fi

echo "PLUGIN_MATRIX:PASS"
