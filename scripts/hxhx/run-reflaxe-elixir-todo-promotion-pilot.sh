#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FETCH_SCRIPT="$ROOT/scripts/vendor/fetch-reflaxe-elixir-upstream.sh"
PROMOTE_SCRIPT="$ROOT/scripts/hxhx/promote-backend-plugin.sh"
OCAMLOPT_WRAPPER="$ROOT/scripts/hxhx/ocamlopt-with-threads.sh"
PILOT_STRICT="${HXHX_PILOT_STRICT:-1}"
ARTIFACT_DIR="${HXHX_PILOT_ARTIFACT_DIR:-}"

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

now_ms() {
  node -e 'process.stdout.write(String(Date.now()))'
}

total_start_ms="$(now_ms)"

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

if [ -n "$ARTIFACT_DIR" ]; then
  mkdir -p "$ARTIFACT_DIR"
fi

source_repo="${REFLAXE_ELIXIR_DIR:-}"
source_commit=""
source_start_ms="$(now_ms)"
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
source_end_ms="$(now_ms)"

todo_src="$source_repo/examples/todo-app/src_haxe"
if [ ! -d "$todo_src" ]; then
  echo "reflaxe-elixir todo pilot: missing todo source dir: $todo_src" >&2
  exit 2
fi

HXHX_BIN_RESOLVED="${HXHX_BIN:-}"
if [ -z "$HXHX_BIN_RESOLVED" ] || { [ ! -x "$HXHX_BIN_RESOLVED" ] && [[ "$HXHX_BIN_RESOLVED" != *.bc ]]; }; then
  HXHX_BIN_RESOLVED="$(bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi
if [ ! -x "$HXHX_BIN_RESOLVED" ] && [[ "$HXHX_BIN_RESOLVED" != *.bc ]]; then
  echo "reflaxe-elixir todo pilot: failed to resolve executable hxhx binary: $HXHX_BIN_RESOLVED" >&2
  exit 2
fi
if [[ "$HXHX_BIN_RESOLVED" == *.bc ]]; then
  require_cmd ocamlrun
  HXHX_CMD=(ocamlrun "$HXHX_BIN_RESOLVED")
  HXHX_MODE="bytecode"
else
  HXHX_CMD=("$HXHX_BIN_RESOLVED")
  HXHX_MODE="native"
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

promoted_out="$tmp_root/promoted"
artifact_ext="cmxs"
if [ "$HXHX_MODE" = "bytecode" ]; then
  artifact_ext="cma"
fi

promote_start_ms="$(now_ms)"
bash "$PROMOTE_SCRIPT" \
  --plugin-id pilot.reflaxe.elixir.todo.plugin \
  --plugin-version 0.1.0 \
  --provider-type backend.js.JsBackend \
  --target-id js-native \
  --artifact-ext "$artifact_ext" \
  --out-dir "$promoted_out"
promote_end_ms="$(now_ms)"

manifest="$promoted_out/backend-plugin.json"
artifact="$promoted_out/plugins/pilot_reflaxe_elixir_todo_plugin.${artifact_ext}"
if [ ! -f "$manifest" ] || [ ! -f "$artifact" ]; then
  echo "reflaxe-elixir todo pilot: missing promoted artifacts" >&2
  exit 2
fi
manifest_sha256="$(shasum -a 256 "$manifest" | awk '{print $1}')"
artifact_sha256="$(shasum -a 256 "$artifact" | awk '{print $1}')"
if [ -n "$ARTIFACT_DIR" ]; then
  cp "$manifest" "$ARTIFACT_DIR/backend-plugin.json"
  printf '%s  %s\n' "$manifest_sha256" "backend-plugin.json" >"$ARTIFACT_DIR/backend-plugin.sha256"
  printf '%s  %s\n' "$artifact_sha256" "$(basename "$artifact")" >"$ARTIFACT_DIR/plugin-artifact.sha256"
  {
    echo "plugin_manifest=$manifest"
    echo "plugin_artifact=$artifact"
    echo "plugin_artifact_ext=$artifact_ext"
    echo "plugin_artifact_sha256=$artifact_sha256"
  } >"$ARTIFACT_DIR/promotion.env"
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

compile_start_ms="$(now_ms)"
set +e
compile_output="$(
  HXHX_FORBID_STAGE0=1 \
    HXHX_TRACE_BACKEND_SELECTION=1 \
    HXHX_TRACE_BACKEND_PROVIDERS=1 \
    "${HXHX_CMD[@]}" \
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
compile_end_ms="$(now_ms)"
printf '%s\n' "$compile_output"
if [ -n "$ARTIFACT_DIR" ]; then
  printf '%s\n' "$compile_output" >"$ARTIFACT_DIR/compile.stdout.log"
fi
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

node_start_ms="$(now_ms)"
node_output="$(node "$out_dir/todo_pilot.js")"
node_end_ms="$(now_ms)"
printf '%s\n' "$node_output"
printf '%s\n' "$node_output" | grep -q '^TODO_PILOT:sum=6$'
if [ -n "$ARTIFACT_DIR" ]; then
  printf '%s\n' "$node_output" >"$ARTIFACT_DIR/node.stdout.log"
  cp "$out_dir/todo_pilot.js" "$ARTIFACT_DIR/todo_pilot.js"
fi

sample_module="$todo_src/server/services/MockOAuthIdentity.hx"
if [ ! -f "$sample_module" ]; then
  echo "reflaxe-elixir todo pilot: expected sample module missing: $sample_module" >&2
  exit 2
fi
sample_hash="$(shasum -a 256 "$sample_module" | awk '{print $1}' | cut -c1-16)"
total_end_ms="$(now_ms)"
if [ -n "$ARTIFACT_DIR" ]; then
  node - "$ARTIFACT_DIR/reflaxe-elixir-promotion-native.summary.json" "$source_repo" "$source_commit" "$todo_src" "$sample_module" "$sample_hash" "$HXHX_BIN_RESOLVED" "$HXHX_MODE" "$manifest_sha256" "$artifact_sha256" "$total_start_ms" "$total_end_ms" "$source_start_ms" "$source_end_ms" "$promote_start_ms" "$promote_end_ms" "$compile_start_ms" "$compile_end_ms" "$node_start_ms" "$node_end_ms" <<'NODE'
const fs = require('fs')
const [
  summaryPath,
  sourceRepo,
  sourceCommit,
  todoSrc,
  sampleModule,
  sampleHash,
  hxhxBin,
  hxhxMode,
  pluginManifestSha256,
  pluginArtifactSha256,
  totalStartMs,
  totalEndMs,
  sourceStartMs,
  sourceEndMs,
  promoteStartMs,
  promoteEndMs,
  compileStartMs,
  compileEndMs,
  nodeStartMs,
  nodeEndMs,
] = process.argv.slice(2)
const seconds = (start, end) => Number(((Number(end) - Number(start)) / 1000).toFixed(3))
fs.writeFileSync(summaryPath, JSON.stringify({
  status: 'pass',
  marker: 'REFLAXE_ELIXIR_PROMOTION_NATIVE:PASS',
  sourceRepo,
  sourceCommit,
  todoSrc,
  sampleModule,
  sampleHash,
  hxhxBin,
  hxhxMode,
  pluginManifestSha256,
  pluginArtifactSha256,
  nodeOutput: 'TODO_PILOT:sum=6',
  timings: {
    totalSeconds: seconds(totalStartMs, totalEndMs),
    sourceResolveSeconds: seconds(sourceStartMs, sourceEndMs),
    pluginPromoteSeconds: seconds(promoteStartMs, promoteEndMs),
    compileSeconds: seconds(compileStartMs, compileEndMs),
    nodeRunSeconds: seconds(nodeStartMs, nodeEndMs),
  },
}, null, 2) + '\n')
NODE
fi

echo "pilot_reflaxe_elixir_repo=$source_repo"
echo "pilot_reflaxe_elixir_commit=$source_commit"
echo "pilot_reflaxe_elixir_src=$todo_src"
echo "pilot_sample_module=$sample_module"
echo "pilot_sample_hash=$sample_hash"
echo "pilot_plugin_manifest=$manifest"
echo "pilot_plugin_artifact=$artifact"
if [ -n "$ARTIFACT_DIR" ]; then
  echo "pilot_artifact_dir=$ARTIFACT_DIR"
fi
echo "PILOT_REFLAXE_ELIXIR_TODO:PASS"
echo "REFLAXE_ELIXIR_PROMOTION_NATIVE:PASS"
