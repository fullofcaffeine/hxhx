#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RPMX_PROOF_SCRIPT="$ROOT/scripts/ci/run-rpmx-haxe-plugin-proof.sh"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${FULL1_PLUGIN_UPSTREAM_HOST_ADAPTER_ARTIFACT_DIR:-$ROOT/.artifacts/full1/plugin-upstream-host-adapter/$RUN_ID}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "full1 plugin upstream host-adapter proof: missing required command: $1" >&2
    exit 1
  fi
}

require_cmd node
require_cmd awk

if [ ! -x "$RPMX_PROOF_SCRIPT" ]; then
  echo "full1 plugin upstream host-adapter proof: missing rpmx proof script: $RPMX_PROOF_SCRIPT" >&2
  exit 1
fi

prefer_local_native_haxe_host() {
  local candidate="$ROOT/vendor/haxe/haxe"
  local candidate_dyld="${RPMX_HAXE_PLUGIN_DYLD_LIBRARY_PATH:-}"
  local mbedtls_prefix=""

  if [ -n "${RPMX_HAXE_PLUGIN_HOST:-}" ] || [ ! -x "$candidate" ]; then
    return 0
  fi

  if [ -z "$candidate_dyld" ] && command -v brew >/dev/null 2>&1; then
    mbedtls_prefix="$(brew --prefix mbedtls@3 2>/dev/null || true)"
    if [ -n "$mbedtls_prefix" ] && [ -d "$mbedtls_prefix/lib" ]; then
      candidate_dyld="$mbedtls_prefix/lib"
      export RPMX_HAXE_PLUGIN_DYLD_LIBRARY_PATH="$candidate_dyld"
    fi
  fi

  if [ -n "$candidate_dyld" ]; then
    if DYLD_LIBRARY_PATH="$candidate_dyld${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$candidate" --version >/dev/null 2>&1; then
      export RPMX_HAXE_PLUGIN_HOST="$candidate"
    fi
  elif "$candidate" --version >/dev/null 2>&1; then
    export RPMX_HAXE_PLUGIN_HOST="$candidate"
  fi

  if [ "${RPMX_HAXE_PLUGIN_HOST:-}" = "$candidate" ] && [ -z "${RPMX_HAXE_PLUGIN_OCAML_ENV:-}" ]; then
    if command -v opam >/dev/null 2>&1; then
      export RPMX_HAXE_PLUGIN_OCAML_ENV=opam
    fi
  fi
}

prefer_local_native_haxe_host

mkdir -p "$ARTIFACT_DIR"

rpmx_stdout="$ARTIFACT_DIR/rpmx.stdout.log"
rpmx_stderr="$ARTIFACT_DIR/rpmx.stderr.log"
summary_json="$ARTIFACT_DIR/full1-plugin-upstream-host-adapter.summary.json"

set +e
bash "$RPMX_PROOF_SCRIPT" >"$rpmx_stdout" 2>"$rpmx_stderr"
rpmx_status="$?"
set -e
if [ "$rpmx_status" -ne 0 ]; then
  echo "full1 plugin upstream host-adapter proof: rpmx upstream Haxe proof failed (exit $rpmx_status)" >&2
  cat "$rpmx_stdout" >&2
  cat "$rpmx_stderr" >&2
  exit "$rpmx_status"
fi

rpmx_summary="$(
  awk -F= '/^rpmx_haxe_plugin_summary=/{print $2}' "$rpmx_stdout" | tail -n 1
)"
if [ -z "$rpmx_summary" ] || [ ! -f "$rpmx_summary" ]; then
  echo "full1 plugin upstream host-adapter proof: failed to resolve rpmx summary from $rpmx_stdout" >&2
  cat "$rpmx_stdout" >&2
  exit 1
fi

ROOT="$ROOT" \
RUN_ID="$RUN_ID" \
RPMX_SUMMARY="$rpmx_summary" \
RPMX_STDOUT="$rpmx_stdout" \
RPMX_STDERR="$rpmx_stderr" \
SUMMARY_JSON="$summary_json" \
node <<'NODE'
const fs = require('fs')

function fail(message) {
  console.error(`full1 plugin upstream host-adapter proof: ${message}`)
  process.exit(1)
}

const rpmxSummaryPath = process.env.RPMX_SUMMARY
const rpmxSummary = JSON.parse(fs.readFileSync(rpmxSummaryPath, 'utf8'))

if (rpmxSummary.result !== 'RPMX_HAXE_PLUGIN:PASS') {
  fail(`unexpected rpmx result: ${rpmxSummary.result}`)
}

if (!rpmxSummary.host?.compilerPath || !rpmxSummary.host?.compilerVersion) {
  fail('rpmx summary is missing the exact host compiler path/version')
}

if (rpmxSummary.proof?.loadStatus !== 'pass') {
  fail(`expected eval host adapter to load an artifact, got loadStatus=${rpmxSummary.proof?.loadStatus}`)
}

if (!rpmxSummary.proof?.loadArtifact) {
  fail('rpmx summary is missing the loaded artifact path')
}

const summary = {
  runId: process.env.RUN_ID,
  proof: 'reflaxe.ocaml upstream Haxe artifact loaded through explicit upstream Haxe eval host adaptation',
  repoRoot: process.env.ROOT,
  artifactCompiler: {
    kind: 'upstream-haxe',
    path: rpmxSummary.host.compilerPath,
    version: rpmxSummary.host.compilerVersion,
    versionProbeStatus: rpmxSummary.host.compilerVersionProbeStatus,
  },
  upstreamHostAdapter: {
    kind: 'haxe-eval',
    loadApi: 'eval.vm.Context.loadPlugin',
    crossHostBinaryCompatibility: false,
    trueCompilerTargetPluginAbi: false,
  },
  source: rpmxSummary.source,
  ocamlToolchain: {
    toolchainMode: rpmxSummary.host.toolchainMode,
    dyldLibraryPathActive: rpmxSummary.host.dyldLibraryPathActive,
    dunePath: rpmxSummary.host.dunePath,
    duneVersion: rpmxSummary.host.duneVersion,
    ocamlcPath: rpmxSummary.host.ocamlcPath,
    ocamlcVersion: rpmxSummary.host.ocamlcVersion,
    ocamloptPath: rpmxSummary.host.ocamloptPath,
    ocamloptVersion: rpmxSummary.host.ocamloptVersion,
  },
  pluginArtifact: {
    layout: rpmxSummary.proof.artifactLayout,
    builtArtifacts: rpmxSummary.proof.builtArtifacts,
    loadedArtifact: rpmxSummary.proof.loadArtifact,
    loadStatus: rpmxSummary.proof.loadStatus,
    requiredGeneratedModules: rpmxSummary.proof.requiredGeneratedModules,
  },
  evidence: {
    upstreamProofSummary: rpmxSummaryPath,
    upstreamProofResult: rpmxSummary.result,
    wrapperStdout: process.env.RPMX_STDOUT,
    wrapperStderr: process.env.RPMX_STDERR,
  },
  nonGoals: [
    'Does not claim a true upstream Haxe compiler-target/native-target plugin ABI.',
    'Does not claim one native plugin binary is portable between upstream Haxe and hxhx.',
    'Does not introduce hxhx stage0 delegation or vendored upstream compiler/test code.',
  ],
  result: 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS',
}

fs.writeFileSync(process.env.SUMMARY_JSON, JSON.stringify(summary, null, 2) + '\n')
NODE

host_path="$(node -e 'const fs=require("fs"); const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(s.artifactCompiler.path)' "$summary_json")"
host_version="$(node -e 'const fs=require("fs"); const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(s.artifactCompiler.version)' "$summary_json")"
load_artifact="$(node -e 'const fs=require("fs"); const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(s.pluginArtifact.loadedArtifact)' "$summary_json")"

echo "full1_plugin_upstream_host_adapter_summary=$summary_json"
echo "full1_plugin_upstream_host_adapter_artifact_compiler=$host_path"
echo "full1_plugin_upstream_host_adapter_artifact_compiler_version=$host_version"
echo "full1_plugin_upstream_host_adapter_load_api=eval.vm.Context.loadPlugin"
echo "full1_plugin_upstream_host_adapter_loaded_artifact=$load_artifact"
echo "REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS"
