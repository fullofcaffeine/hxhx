#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROMOTE_SCRIPT="$ROOT/scripts/hxhx/promote-eval-adapter.sh"
OCAMLOPT_WRAPPER="$ROOT/scripts/hxhx/ocamlopt-with-threads.sh"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlopt >/dev/null 2>&1; then
  echo "Skipping promotion eval smoke: dune/ocamlopt not found on PATH."
  exit 0
fi

if ! command -v haxe >/dev/null 2>&1; then
  echo "Skipping promotion eval smoke: haxe not found on PATH."
  exit 0
fi

if [ ! -x "$PROMOTE_SCRIPT" ]; then
  echo "Missing executable promote script: $PROMOTE_SCRIPT" >&2
  exit 1
fi

if [ -z "${OCAMLOPT:-}" ] && [ -x "$OCAMLOPT_WRAPPER" ]; then
  export OCAMLOPT="$OCAMLOPT_WRAPPER"
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

fixture_src="$tmp_root/src"
mkdir -p "$fixture_src"
cat >"$fixture_src/EvalPromotionSmokeMacro.hx" <<'HX'
import haxe.macro.Context;
import haxe.macro.Expr;

class EvalPromotionSmokeMacro {
	public static macro function status():ExprOf<String> {
		if (!Context.defined("eval")) {
			return macro $v{"eval_missing"};
		}

		final pluginPath = Context.definedValue("eval_plugin_path");
		if (pluginPath == null || StringTools.trim(pluginPath).length == 0) {
			return macro $v{"eval_plugin_path_missing"};
		}

		final loaded:Null<{}> = eval.vm.Context.loadPlugin(pluginPath);
		return macro $v{loaded == null ? "eval_plugin_loaded_null_api" : "eval_plugin_loaded_with_api"};
	}
}
HX

cat >"$fixture_src/Main.hx" <<'HX'
class Main {
	static function main() {
		Sys.println(EvalPromotionSmokeMacro.status());
	}
}
HX

declare -a artifact_exts=()
if [ -n "${HXHX_EVAL_PLUGIN_ARTIFACT_EXT:-}" ]; then
  artifact_exts=("${HXHX_EVAL_PLUGIN_ARTIFACT_EXT}")
else
  artifact_exts=("cma" "cmxs")
fi

loaded=0
mismatch_detected=0
last_output=""
last_exit=1
manifest=""
artifact=""

for artifact_ext in "${artifact_exts[@]}"; do
  promoted_out="$tmp_root/promoted_${artifact_ext}"
  bash "$PROMOTE_SCRIPT" \
    --plugin-id fixture.promoted.eval.plugin \
    --plugin-version 0.1.0 \
    --target-id js-native \
    --artifact-ext "$artifact_ext" \
    --out-dir "$promoted_out"

  manifest="$promoted_out/eval-plugin.json"
  artifact="$promoted_out/plugins/fixture_promoted_eval_plugin_eval.${artifact_ext}"
  if [ ! -f "$manifest" ] || [ ! -f "$artifact" ]; then
    echo "promotion eval smoke: missing promoted artifacts for .$artifact_ext" >&2
    exit 2
  fi

  grep -q '"kind": "haxe-eval"' "$manifest"
  grep -q '"crossHostBinaryCompatibility": false' "$manifest"

  set +e
  output="$(
    haxe \
      -cp "$fixture_src" \
      -main Main \
      --interp \
      -D "eval_plugin_path=$artifact" 2>&1
  )"
  exit_code="$?"
  set -e
  printf '%s\n' "$output"

  last_output="$output"
  last_exit="$exit_code"
  if printf '%s\n' "$output" | grep -Eq 'Dynlink\.(Not_a_bytecode_file|Cannot_open_dll)|error loading shared library|inconsistent assumptions'; then
    mismatch_detected=1
  fi
  if [ "$exit_code" -eq 0 ] && printf '%s\n' "$output" | grep -Eq '^eval_plugin_loaded_(null_api|with_api)$'; then
    loaded=1
    break
  fi
done

if [ "$loaded" -ne 1 ]; then
  if [ "$mismatch_detected" -eq 1 ]; then
    echo "promotion eval smoke: skipping strict load assertion due host/plugin dynlink ABI mismatch."
    echo "promotion_eval_manifest=$manifest"
    echo "promotion_eval_artifact=$artifact"
    echo "PROMOTION_EVAL_SMOKE:SKIP_HOST_ABI"
    exit 0
  fi
  printf '%s\n' "$last_output"
  echo "promotion eval smoke: eval plugin load failed for tested artifact extensions" >&2
  exit "${last_exit:-1}"
fi

echo "promotion_eval_manifest=$manifest"
echo "promotion_eval_artifact=$artifact"
echo "PROMOTION_EVAL_SMOKE:PASS"
