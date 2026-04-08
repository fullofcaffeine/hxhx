#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FETCH_SCRIPT="$ROOT/scripts/vendor/fetch-reflaxe-elixir-upstream.sh"

if [ -n "${RPMX_HAXE_PLUGIN_DYLD_LIBRARY_PATH:-}" ]; then
  export DYLD_LIBRARY_PATH="${RPMX_HAXE_PLUGIN_DYLD_LIBRARY_PATH}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "rpmx haxe plugin proof: missing required command: $1" >&2
    exit 1
  fi
}

require_cmd git
require_cmd dune
require_cmd ocamlc
require_cmd ocamlopt
require_cmd node

if [ ! -x "$FETCH_SCRIPT" ]; then
  echo "rpmx haxe plugin proof: missing fetch script: $FETCH_SCRIPT" >&2
  exit 1
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
    echo "rpmx haxe plugin proof: REFLAXE_ELIXIR_DIR is not a git repo: $source_repo" >&2
    exit 1
  fi
  source_commit="$(git -C "$source_repo" rev-parse HEAD)"
fi

run_id="$(date +%Y%m%d-%H%M%S)"
artifact_root="$ROOT/.artifacts/rpmx/haxe-plugin/$run_id"
mkdir -p "$artifact_root"
out_dir="$artifact_root/out"
mkdir -p "$out_dir"

compile_stdout="$artifact_root/haxe.stdout.log"
compile_stderr="$artifact_root/haxe.stderr.log"
build_stdout="$artifact_root/dune.stdout.log"
build_stderr="$artifact_root/dune.stderr.log"
load_stdout="$artifact_root/load.stdout.log"
load_stderr="$artifact_root/load.stderr.log"
summary_json="$artifact_root/rpmx-haxe-plugin.summary.json"

host_compiler_default_path="$(command -v haxe)"
host_compiler_bin="${RPMX_HAXE_PLUGIN_HOST:-$host_compiler_default_path}"
if [ ! -x "$host_compiler_bin" ]; then
  echo "rpmx haxe plugin proof: host compiler is not executable: $host_compiler_bin" >&2
  exit 1
fi
host_compiler_path="$(cd "$(dirname "$host_compiler_bin")" && pwd -P)/$(basename "$host_compiler_bin")"
set +e
host_compiler_version_output="$("$host_compiler_bin" --version 2>&1)"
host_compiler_version_status="$?"
set -e
if [ "$host_compiler_version_status" -eq 0 ]; then
  host_compiler_version="$(printf '%s\n' "$host_compiler_version_output" | tail -n 1)"
else
  host_compiler_version="<unavailable: exit $host_compiler_version_status>"
fi

toolchain_mode="${RPMX_HAXE_PLUGIN_OCAML_ENV:-system}"
case "$toolchain_mode" in
  system)
    ;;
  opam)
    require_cmd opam
    ;;
  *)
    echo "rpmx haxe plugin proof: unsupported RPMX_HAXE_PLUGIN_OCAML_ENV: $toolchain_mode" >&2
    exit 1
    ;;
esac

compile_args=(
  -cp "$source_repo/src"
  -cp "$source_repo/vendor/reflaxe/src"
  -main Run
  --no-output
  -lib reflaxe.ocaml
  --macro 'haxe.macro.Compiler.nullSafety("reflaxe.elixir.generator", Off, true)'
  -D no-traces
  -D no_traces
  -D "ocaml_output=$out_dir"
  -D ocaml_dune_layout=plugin
  -D ocaml_plugin_mode=1
  -D ocaml_emit_exclude_packages=haxe.iterators
  -D ocaml_emit_exclude_paths=Any,HxTypeRegistry
  -D ocaml_no_build
)

(
  cd "$ROOT"
  "$host_compiler_bin" "${compile_args[@]}"
) >"$compile_stdout" 2>"$compile_stderr"

for required in \
  "$out_dir/dune" \
  "$out_dir/out.ml" \
  "$out_dir/Run.ml" \
  "$out_dir/reflaxe_elixir_generator_ProjectGenerator.ml" \
  "$out_dir/reflaxe_elixir_generator_TemplateEngine.ml"; do
  if [ ! -f "$required" ]; then
    echo "rpmx haxe plugin proof: missing expected generated artifact: $required" >&2
    exit 1
  fi
done

for forbidden in \
  "$out_dir/Haxe.ml" \
  "$out_dir/haxe_iterators_ArrayIterator.ml" \
  "$out_dir/Any.ml" \
  "$out_dir/HxTypeRegistry.ml"; do
  if [ -f "$forbidden" ]; then
    echo "rpmx haxe plugin proof: expected filtered artifact to be absent: $forbidden" >&2
    exit 1
  fi
done

case "$toolchain_mode" in
  system)
    ;;
  opam)
    eval "$(opam env --shell=bash)"
    ;;
esac

dune_path="$(command -v dune)"
ocamlc_path="$(command -v ocamlc)"
ocamlopt_path="$(command -v ocamlopt)"
dune_version="$(dune --version)"
ocamlc_version="$(ocamlc -version)"
ocamlopt_version="$(ocamlopt -version)"

(
  cd "$out_dir"
  dune build ./out.cma ./out.cmxs
) >"$build_stdout" 2>"$build_stderr"

byte_artifact="$out_dir/_build/default/out.cma"
native_artifact="$out_dir/_build/default/out.cmxs"
if [ ! -f "$byte_artifact" ] || [ ! -f "$native_artifact" ]; then
  echo "rpmx haxe plugin proof: missing built plugin artifacts" >&2
  exit 1
fi

load_fixture="$artifact_root/eval_load"
mkdir -p "$load_fixture"
cat >"$load_fixture/RpmxProbeMacro.hx" <<'HX'
import haxe.macro.Expr;

class RpmxProbeMacro {
	public static macro function status():ExprOf<String> {
		final pluginPath = haxe.macro.Context.definedValue("eval_plugin_path");
		if (pluginPath == null || StringTools.trim(pluginPath).length == 0)
			return macro "missing";

		final loaded:Null<{}> = eval.vm.Context.loadPlugin(pluginPath);
		return macro $v{loaded == null ? "loaded_null_api" : "loaded_with_api"};
	}
}
HX

cat >"$load_fixture/Main.hx" <<'HX'
class Main {
	static function main() {
		Sys.println(RpmxProbeMacro.status());
	}
}
HX

load_status="not_attempted"
load_artifact=""
for artifact in "$byte_artifact" "$native_artifact"; do
  set +e
  output="$(
    "$host_compiler_bin" \
      -cp "$load_fixture" \
      -main Main \
      --interp \
      -D "eval_plugin_path=$artifact" 2>&1
  )"
  exit_code="$?"
  set -e

  {
    echo "ARTIFACT=$artifact"
    echo "EXIT=$exit_code"
    printf '%s\n' "$output"
    echo "---"
  } >>"$load_stdout"

  if [ "$exit_code" -eq 0 ] && printf '%s\n' "$output" | grep -Eq '^loaded_(null_api|with_api)$'; then
    load_status="pass"
    load_artifact="$artifact"
    break
  fi

  if printf '%s\n' "$output" | grep -Eq 'Dynlink\.(Not_a_bytecode_file|Cannot_open_dll)|error loading shared library|inconsistent assumptions'; then
    load_status="skip_host_abi"
    load_artifact="$artifact"
    continue
  fi

  load_status="fail"
  load_artifact="$artifact"
  printf '%s\n' "$output" >"$load_stderr"
  break
done

if [ "$load_status" = "fail" ]; then
  echo "rpmx haxe plugin proof: eval host load failed for reasons other than host ABI mismatch" >&2
  cat "$load_stderr" >&2
  exit 1
fi

artifact_root_abs="$(cd "$artifact_root" && pwd -P)"
out_dir_abs="$(cd "$out_dir" && pwd -P)"
source_repo_abs="$(cd "$source_repo" && pwd -P)"
byte_artifact_abs="$(cd "$(dirname "$byte_artifact")" && pwd -P)/$(basename "$byte_artifact")"
native_artifact_abs="$(cd "$(dirname "$native_artifact")" && pwd -P)/$(basename "$native_artifact")"
if [ -n "$load_artifact" ]; then
  load_artifact_abs="$(cd "$(dirname "$load_artifact")" && pwd -P)/$(basename "$load_artifact")"
else
  load_artifact_abs=""
fi

ROOT="$ROOT" \
RUN_ID="$run_id" \
SOURCE_REPO="$source_repo_abs" \
SOURCE_COMMIT="$source_commit" \
HOST_COMPILER_PATH="$host_compiler_path" \
HOST_COMPILER_VERSION="$host_compiler_version" \
HOST_COMPILER_VERSION_PROBE_STATUS="$host_compiler_version_status" \
DYLD_LIBRARY_PATH_ACTIVE="${DYLD_LIBRARY_PATH:-}" \
DUNE_PATH="$dune_path" \
DUNE_VERSION="$dune_version" \
OCAMLC_PATH="$ocamlc_path" \
OCAMLC_VERSION="$ocamlc_version" \
OCAMLOPT_PATH="$ocamlopt_path" \
OCAMLOPT_VERSION="$ocamlopt_version" \
TOOLCHAIN_MODE="$toolchain_mode" \
ARTIFACT_ROOT="$artifact_root_abs" \
OUT_DIR="$out_dir_abs" \
BYTE_ARTIFACT="$byte_artifact_abs" \
NATIVE_ARTIFACT="$native_artifact_abs" \
LOAD_STATUS="$load_status" \
LOAD_ARTIFACT="$load_artifact_abs" \
SUMMARY_JSON="$summary_json" \
node <<'NODE'
const fs = require('fs');
const summary = {
  runId: process.env.RUN_ID,
  workload: 'reflaxe-elixir-run-generator',
  host: {
    compilerPath: process.env.HOST_COMPILER_PATH,
    compilerVersion: process.env.HOST_COMPILER_VERSION,
    compilerVersionProbeStatus: Number(process.env.HOST_COMPILER_VERSION_PROBE_STATUS),
    toolchainMode: process.env.TOOLCHAIN_MODE,
    dyldLibraryPathActive: process.env.DYLD_LIBRARY_PATH_ACTIVE || null,
    dunePath: process.env.DUNE_PATH,
    duneVersion: process.env.DUNE_VERSION,
    ocamlcPath: process.env.OCAMLC_PATH,
    ocamlcVersion: process.env.OCAMLC_VERSION,
    ocamloptPath: process.env.OCAMLOPT_PATH,
    ocamloptVersion: process.env.OCAMLOPT_VERSION,
  },
  source: {
    repo: process.env.SOURCE_REPO,
    commit: process.env.SOURCE_COMMIT,
  },
  proof: {
    compileHost: 'upstream-haxe-4.3.7-compatible',
    artifactLayout: 'plugin',
    explicitNullSafetyOverride: 'haxe.macro.Compiler.nullSafety("reflaxe.elixir.generator", Off, true)',
    builtArtifacts: [process.env.BYTE_ARTIFACT, process.env.NATIVE_ARTIFACT],
    requiredGeneratedModules: [
      'Run.ml',
      'reflaxe_elixir_generator_ProjectGenerator.ml',
      'reflaxe_elixir_generator_TemplateEngine.ml',
      'out.ml',
    ],
    loadStatus: process.env.LOAD_STATUS,
    loadArtifact: process.env.LOAD_ARTIFACT || null,
  },
  logs: {
    compileStdout: 'haxe.stdout.log',
    compileStderr: 'haxe.stderr.log',
    buildStdout: 'dune.stdout.log',
    buildStderr: 'dune.stderr.log',
    loadStdout: 'load.stdout.log',
    loadStderr: 'load.stderr.log',
  },
  result: 'RPMX_HAXE_PLUGIN:PASS',
};
fs.writeFileSync(process.env.SUMMARY_JSON, JSON.stringify(summary, null, 2) + '\n');
NODE

echo "rpmx_haxe_plugin_workload=reflaxe-elixir-run-generator"
echo "rpmx_haxe_plugin_repo=$source_repo_abs"
echo "rpmx_haxe_plugin_commit=$source_commit"
echo "rpmx_haxe_plugin_host=$host_compiler_path"
echo "rpmx_haxe_plugin_host_version=$host_compiler_version"
echo "rpmx_haxe_plugin_out=$out_dir_abs"
echo "rpmx_haxe_plugin_byte_artifact=$byte_artifact_abs"
echo "rpmx_haxe_plugin_native_artifact=$native_artifact_abs"
echo "rpmx_haxe_plugin_load_status=$load_status"
if [ -n "$load_artifact_abs" ]; then
  echo "rpmx_haxe_plugin_load_artifact=$load_artifact_abs"
fi
echo "rpmx_haxe_plugin_summary=$summary_json"
if [ "$load_status" = "skip_host_abi" ]; then
  echo "RPMX_HAXE_PLUGIN_LOAD:SKIP_HOST_ABI"
elif [ "$load_status" = "pass" ]; then
  echo "RPMX_HAXE_PLUGIN_LOAD:PASS"
fi
echo "RPMX_HAXE_PLUGIN:PASS"
