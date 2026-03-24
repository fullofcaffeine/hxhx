#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v haxe >/dev/null 2>&1; then
  echo "Skipping macro-module dynlink smoke: haxe not found on PATH."
  exit 0
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping macro-module dynlink smoke: dune/ocamlc not found on PATH."
  exit 0
fi

HXHX_MACRO_HOST_EXE_RESOLVED="${HXHX_MACRO_HOST_EXE:-}"
if [ -z "$HXHX_MACRO_HOST_EXE_RESOLVED" ] || [ ! -x "$HXHX_MACRO_HOST_EXE_RESOLVED" ]; then
  HXHX_MACRO_HOST_EXE_RESOLVED="$(HXHX_MACRO_HOST_FORCE_STAGE0=1 bash "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
fi
if [ -z "$HXHX_MACRO_HOST_EXE_RESOLVED" ] || [ ! -x "$HXHX_MACRO_HOST_EXE_RESOLVED" ]; then
  echo "Failed to resolve executable hxhx macro host binary: $HXHX_MACRO_HOST_EXE_RESOLVED" >&2
  exit 2
fi

macro_host_build_dir="$(dirname "$HXHX_MACRO_HOST_EXE_RESOLVED")"
runtime_cmi_dir="$macro_host_build_dir/runtime/.hx_runtime.objs/byte"
if [ ! -d "$runtime_cmi_dir" ]; then
  echo "Macro-module dynlink smoke requires runtime CMI directory: $runtime_cmi_dir" >&2
  exit 2
fi

artifact_ext="cmxs"
case "$HXHX_MACRO_HOST_EXE_RESOLVED" in
  *.bc)
    artifact_ext="cma"
    ;;
esac

if [ "$artifact_ext" = "cmxs" ] && ! command -v ocamlopt >/dev/null 2>&1; then
  echo "Skipping macro-module dynlink smoke: ocamlopt not found for .cmxs build."
  exit 0
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

good_src="$tmp_root/native_macro_good.ml"
bad_src="$tmp_root/native_macro_bad.ml"
good_artifact="$tmp_root/native_macro_good.${artifact_ext}"
bad_artifact="$tmp_root/native_macro_bad.${artifact_ext}"

cat >"$good_src" <<'ML'
let plugin_id : string = "fixture.native.macro.plugin"

let () =
  HxHxMacroModuleHost.register_expr_handler plugin_id
    "FixtureNativeMacroPlugin.smoke()"
    (fun () -> "native_macro_smoke_ok")
ML

cat >"$bad_src" <<'ML'
let plugin_id : string = "fixture.native.macro.other"

let () =
  HxHxMacroModuleHost.register_expr_handler plugin_id
    "FixtureNativeMacroPlugin.bad()"
    (fun () -> "native_macro_bad")
ML

build_native_macro_artifact() {
  local src="$1"
  local out="$2"
  local stem="$3"
  if [ "$artifact_ext" = "cmxs" ]; then
    ocamlopt -I "$runtime_cmi_dir" -c "$src" -o "$tmp_root/${stem}.cmx"
    ocamlopt -shared "$tmp_root/${stem}.cmx" -o "$out"
  else
    ocamlc -I "$runtime_cmi_dir" -c "$src" -o "$tmp_root/${stem}.cmo"
    ocamlc -a "$tmp_root/${stem}.cmo" -o "$out"
  fi
}

build_native_macro_artifact "$good_src" "$good_artifact" "native_macro_good"
build_native_macro_artifact "$bad_src" "$bad_artifact" "native_macro_bad"

mkdir -p "$tmp_root/dynlinksmoke"
client_src="$tmp_root/dynlinksmoke/DynlinkSmokeMain.hx"
cat >"$client_src" <<'HX'
package dynlinksmoke;

import hxhx.macro.MacroHostClient;

class DynlinkSmokeMain {
	static function fail(message:String):Void {
		throw message;
	}

	static function expectFailureContains(label:String, expected:String, fn:Void->Void):Void {
		var message = "";
		try {
			fn();
		} catch (error:haxe.Exception) {
			message = error.message;
		} catch (error:String) {
			message = error;
		}
		if (message.length == 0)
			fail(label + ": expected failure");
		if (message.indexOf(expected) == -1)
			fail(label + ": expected message containing `" + expected + "`, got `" + message + "`");
	}

	static function main():Void {
		final modulePath = Sys.getEnv("HXHX_NATIVE_MACRO_GOOD");
		final badPath = Sys.getEnv("HXHX_NATIVE_MACRO_BAD");
		final pluginId = "fixture.native.macro.plugin";
		final expr = "FixtureNativeMacroPlugin.smoke()";
		if (modulePath == null || modulePath.length == 0)
			fail("missing HXHX_NATIVE_MACRO_GOOD");
		if (badPath == null || badPath.length == 0)
			fail("missing HXHX_NATIVE_MACRO_BAD");

		final exprs = MacroHostClient.loadNativeModule(modulePath, pluginId);
		if (exprs.length != 1)
			fail("expected one registered expr");
		if (exprs[0] != expr)
			fail("unexpected registered expr: " + exprs[0]);
		Sys.println("macro_native_expr_count=" + exprs.length);
		Sys.println("macro_native_expr[0]=" + exprs[0]);

		final runResult = MacroHostClient.runNativeModuleExpr(modulePath, pluginId, expr);
		Sys.println("macro_native_run=" + runResult);

		expectFailureContains("plugin-id mismatch", "registration pluginId mismatch", function() {
			MacroHostClient.loadNativeModule(badPath, pluginId);
		});
		Sys.println("macro_native_mismatch=ok");

		expectFailureContains("missing entrypoint", "native macro expr not registered", function() {
			MacroHostClient.runNativeModuleExpr(modulePath, pluginId, "FixtureNativeMacroPlugin.missing()");
		});
		Sys.println("macro_native_missing_entry=ok");
	}
}
HX

set +e
client_output="$(
  HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE_RESOLVED" \
    HXHX_NATIVE_MACRO_GOOD="$good_artifact" \
    HXHX_NATIVE_MACRO_BAD="$bad_artifact" \
    haxe -cp "$tmp_root" -cp "$ROOT/packages/hxhx/src" -cp "$ROOT/packages/hxhx-core/src" -main dynlinksmoke.DynlinkSmokeMain --interp 2>&1
)"
client_code="$?"
set -e
printf '%s\n' "$client_output"
if [ "$client_code" -ne 0 ]; then
  echo "macro-module dynlink smoke: client run failed" >&2
  exit "$client_code"
fi

printf '%s\n' "$client_output" | grep -q '^macro_native_expr_count=1$'
printf '%s\n' "$client_output" | grep -q '^macro_native_expr\[0\]=FixtureNativeMacroPlugin.smoke()$'
printf '%s\n' "$client_output" | grep -q '^macro_native_run=native_macro_smoke_ok$'
printf '%s\n' "$client_output" | grep -q '^macro_native_mismatch=ok$'
printf '%s\n' "$client_output" | grep -q '^macro_native_missing_entry=ok$'

echo "macro_native_good_artifact=$good_artifact"
echo "macro_native_bad_artifact=$bad_artifact"
echo "MACRO_MODULE_DYNLINK_SMOKE:PASS"
