#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FETCH_SCRIPT="$ROOT/scripts/vendor/fetch-reflaxe-elixir-upstream.sh"
PROMOTE_SCRIPT="$ROOT/scripts/hxhx/promote-backend-plugin.sh"
OCAMLOPT_WRAPPER="$ROOT/scripts/hxhx/ocamlopt-with-threads.sh"
PILOT_STRICT="${HXHX_PILOT_STRICT:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "reflaxe-elixir todo pilot: missing required command: $1" >&2
    exit 1
  fi
}

require_cmd git
require_cmd node
require_cmd dune
require_cmd ocamlopt
require_cmd haxe

if [ ! -x "$FETCH_SCRIPT" ]; then
  echo "reflaxe-elixir todo pilot: missing fetch script: $FETCH_SCRIPT" >&2
  exit 1
fi
if [ ! -x "$PROMOTE_SCRIPT" ]; then
  echo "reflaxe-elixir todo pilot: missing promotion script: $PROMOTE_SCRIPT" >&2
  exit 1
fi

if [ -z "${OCAMLOPT:-}" ] && [ -x "$OCAMLOPT_WRAPPER" ]; then
  export OCAMLOPT="$OCAMLOPT_WRAPPER"
fi

source_repo="${REFLAXE_ELIXIR_DIR:-}"
source_commit=""
if [ -z "$source_repo" ]; then
  fetch_output="$(bash "$FETCH_SCRIPT")"
  printf '%s\n' "$fetch_output"
  source_repo="$(printf '%s\n' "$fetch_output" | awk -F= '/^reflaxe_elixir_dir=/{print $2}' | tail -n1)"
  source_commit="$(printf '%s\n' "$fetch_output" | awk -F= '/^reflaxe_elixir_commit=/{print $2}' | tail -n1)"
else
  if [ ! -d "$source_repo/.git" ]; then
    echo "reflaxe-elixir todo pilot: REFLAXE_ELIXIR_DIR is not a git repo: $source_repo" >&2
    exit 2
  fi
  source_commit="$(git -C "$source_repo" rev-parse HEAD)"
fi

todo_src="$source_repo/examples/todo-app/src_haxe"
if [ ! -d "$todo_src" ]; then
  echo "reflaxe-elixir todo pilot: missing todo source dir: $todo_src" >&2
  exit 2
fi

HXHX_BIN_RESOLVED="${HXHX_BIN:-}"
if [ -z "$HXHX_BIN_RESOLVED" ] || [ ! -x "$HXHX_BIN_RESOLVED" ]; then
  HXHX_BIN_RESOLVED="$(bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi
if [ ! -x "$HXHX_BIN_RESOLVED" ]; then
  echo "reflaxe-elixir todo pilot: failed to resolve executable hxhx binary: $HXHX_BIN_RESOLVED" >&2
  exit 2
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

promoted_out="$tmp_root/promoted"
artifact_ext="cmxs"
case "$HXHX_BIN_RESOLVED" in
  *.bc)
    artifact_ext="cma"
    ;;
esac

bash "$PROMOTE_SCRIPT" \
  --plugin-id pilot.reflaxe.elixir.todo.plugin \
  --plugin-version 0.1.0 \
  --provider-type backend.js.JsBackend \
  --target-id js-native \
  --artifact-ext "$artifact_ext" \
  --out-dir "$promoted_out"

manifest="$promoted_out/backend-plugin.json"
artifact="$promoted_out/plugins/pilot_reflaxe_elixir_todo_plugin.${artifact_ext}"
if [ ! -f "$manifest" ] || [ ! -f "$artifact" ]; then
  echo "reflaxe-elixir todo pilot: missing promoted artifacts" >&2
  exit 2
fi

harness_src="$tmp_root/harness"
mkdir -p "$harness_src"
cat >"$harness_src/Main.hx" <<'HX'
class Main {
	static function main() {
		var sum = 0;
		for (i in 1...4)
			sum += i;
		Sys.println("TODO_PILOT:sum=" + sum);
	}
}
HX

out_dir="$tmp_root/out"
mkdir -p "$out_dir"

set +e
compile_output="$(
  HXHX_FORBID_STAGE0=1 \
    HXHX_TRACE_BACKEND_SELECTION=1 \
    HXHX_TRACE_BACKEND_PROVIDERS=1 \
    "$HXHX_BIN_RESOLVED" \
      --target js \
      --js "$out_dir/todo_pilot.js" \
      --hxhx-no-run \
      -cp "$todo_src" \
      -cp "$harness_src" \
      -main Main \
      --hxhx-out "$out_dir" \
      -D "hxhx_backend_provider=backend.js.JsBackend" \
      -D "hxhx_backend_plugin_manifest=$manifest" 2>&1
)"
compile_code="$?"
set -e
printf '%s\n' "$compile_output"
if [ "$compile_code" -ne 0 ]; then
  if printf '%s\n' "$compile_output" | grep -q 'js-native:unsupported_expr.*detail=function'; then
    echo "pilot_blocker=js-native function-expression lowering is not yet available in this Stage3 lane"
    echo "PILOT_REFLAXE_ELIXIR_TODO:BLOCKED"
    if [ "$PILOT_STRICT" = "1" ]; then
      echo "pilot_mode=strict (default). Set HXHX_PILOT_STRICT=0 for report-only blocker mode." >&2
      exit 4
    fi
    exit 0
  fi
  echo "reflaxe-elixir todo pilot: stage3 compile failed" >&2
  exit "$compile_code"
fi
printf '%s\n' "$compile_output" | grep -q '^backend_selected_impl=provider/js-native-wrapper$'

node_output="$(node "$out_dir/todo_pilot.js")"
printf '%s\n' "$node_output"
printf '%s\n' "$node_output" | grep -q '^TODO_PILOT:sum=6$'

sample_module="$todo_src/server/services/MockOAuthIdentity.hx"
if [ ! -f "$sample_module" ]; then
  echo "reflaxe-elixir todo pilot: expected sample module missing: $sample_module" >&2
  exit 2
fi
sample_hash="$(shasum -a 256 "$sample_module" | awk '{print $1}' | cut -c1-16)"

echo "pilot_reflaxe_elixir_repo=$source_repo"
echo "pilot_reflaxe_elixir_commit=$source_commit"
echo "pilot_reflaxe_elixir_src=$todo_src"
echo "pilot_sample_module=$sample_module"
echo "pilot_sample_hash=$sample_hash"
echo "pilot_plugin_manifest=$manifest"
echo "pilot_plugin_artifact=$artifact"
echo "PILOT_REFLAXE_ELIXIR_TODO:PASS"
