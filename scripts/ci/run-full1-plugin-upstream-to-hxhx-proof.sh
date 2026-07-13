#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_HXHX_SCRIPT="$ROOT/scripts/hxhx/build-hxhx.sh"
OCAMLOPT_WRAPPER="$ROOT/scripts/hxhx/ocamlopt-with-threads.sh"
ABI_FILE="$ROOT/packages/hxhx-core/src/backend/BackendAbi.hx"

PLUGIN_ID="full1.reflaxe.ocaml.upstream"
PROVIDER_TYPE="backend.js.JsBackend"
TARGET_ID="js-native"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${FULL1_PLUGIN_UPSTREAM_ARTIFACT_DIR:-$ROOT/.artifacts/full1/plugin-upstream-to-hxhx/$RUN_ID}"
KEEP_TMP="${FULL1_PLUGIN_UPSTREAM_KEEP_TMP:-0}"
CANDIDATE_SHA="${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}"
WORKFLOW_RUN_ID="${GITHUB_RUN_ID:-local}"
WORKFLOW_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "full1 plugin upstream-to-hxhx proof: missing required command: $1" >&2
    exit 1
  fi
}

read_abi_const() {
  local name="$1"
  local value
  value="$(grep -E "public[[:space:]]+static[[:space:]]+inline[[:space:]]+var[[:space:]]+$name:Int[[:space:]]*=" "$ABI_FILE" | head -n 1 | sed -E 's/.*=[[:space:]]*([0-9]+).*/\1/')"
  if [ -z "$value" ]; then
    echo "full1 plugin upstream-to-hxhx proof: failed to read $name from $ABI_FILE" >&2
    exit 1
  fi
  printf '%s' "$value"
}

resolve_hxhx_bin() {
  local candidate="${FULL1_PLUGIN_UPSTREAM_HXHX_BIN:-${HXHX_BIN:-}}"
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in \
    "$ROOT/packages/hxhx/bootstrap_work/_build/default/out.exe" \
    "$ROOT/packages/hxhx/bootstrap_work/_build/default/out.bc" \
    "$ROOT/packages/hxhx/out/_build/default/out.exe" \
    "$ROOT/packages/hxhx/out/_build/default/out.bc"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if [ ! -x "$BUILD_HXHX_SCRIPT" ]; then
    echo "full1 plugin upstream-to-hxhx proof: missing hxhx build script: $BUILD_HXHX_SCRIPT" >&2
    exit 1
  fi

  HXHX_STAGE0_FAILFAST_SECS="${FULL1_PLUGIN_UPSTREAM_HXHX_BUILD_FAILFAST_SECS:-1800}" \
    bash "$BUILD_HXHX_SCRIPT" | tail -n 1
}

json_escape() {
  node -e 'process.stdout.write(JSON.stringify(process.argv[1]).slice(1, -1))' "$1"
}

require_cmd haxe
require_cmd dune
require_cmd ocamlc
require_cmd ocamlopt
require_cmd node
require_cmd shasum

if [ ! -f "$ABI_FILE" ]; then
  echo "full1 plugin upstream-to-hxhx proof: missing ABI file: $ABI_FILE" >&2
  exit 1
fi

if [ -z "${OCAMLOPT:-}" ] && [ -x "$OCAMLOPT_WRAPPER" ]; then
  export OCAMLOPT="$OCAMLOPT_WRAPPER"
fi

mkdir -p "$ARTIFACT_DIR"
tmp_root="$(mktemp -d)"
cleanup() {
  if [ "$KEEP_TMP" = "1" ]; then
    echo "full1_plugin_upstream_tmp=$tmp_root"
  else
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

src_dir="$tmp_root/src"
plugin_generated_dir="$tmp_root/plugin-generated"
plugin_out_dir="$tmp_root/plugin-out"
compile_src_dir="$tmp_root/compile-src"
compile_out_dir="$tmp_root/compile-out"
mkdir -p "$src_dir" "$plugin_generated_dir" "$plugin_out_dir/plugins" "$compile_src_dir" "$compile_out_dir"

cat >"$src_dir/PluginEntry.hx" <<'HX'
class PluginEntry {
	static function main():Void {
	}
}
HX

cat >"$compile_src_dir/Main.hx" <<'HX'
class Main {
	static function main() {
		var sum = 0;
		for (i in 1...4)
			sum += i;
		Sys.println("sum=" + sum);
	}
}
HX

haxe_bin="$(command -v haxe)"
haxe_version="$("$haxe_bin" --version 2>&1 | tail -n 1)"
dune_path="$(command -v dune)"
dune_version="$(dune --version)"
ocamlc_path="$(command -v ocamlc)"
ocamlc_version="$(ocamlc -version)"
ocamlopt_path="$(command -v ocamlopt)"
ocamlopt_version="$(ocamlopt -version)"
hxhx_bin="$(resolve_hxhx_bin)"
if [ -z "$hxhx_bin" ] || [ ! -x "$hxhx_bin" ]; then
  echo "full1 plugin upstream-to-hxhx proof: failed to resolve executable hxhx binary: $hxhx_bin" >&2
  exit 1
fi

artifact_ext="cmxs"
case "$hxhx_bin" in
  *.bc)
    artifact_ext="cma"
    ;;
esac

compile_stdout="$ARTIFACT_DIR/upstream-haxe.stdout.log"
compile_stderr="$ARTIFACT_DIR/upstream-haxe.stderr.log"
build_stdout="$ARTIFACT_DIR/dune.stdout.log"
build_stderr="$ARTIFACT_DIR/dune.stderr.log"
hxhx_stdout="$ARTIFACT_DIR/hxhx.stdout.log"
hxhx_stderr="$ARTIFACT_DIR/hxhx.stderr.log"
node_stdout="$ARTIFACT_DIR/node.stdout.log"
summary_json="$ARTIFACT_DIR/full1-plugin-upstream-to-hxhx.summary.json"

(
  cd "$ROOT"
  "$haxe_bin" \
    -cp "$src_dir" \
	    -main PluginEntry \
	    --no-output \
	    -lib reflaxe.ocaml \
	    -D "ocaml_output=$plugin_generated_dir" \
	    -D ocaml_dune_layout=plugin \
	    -D ocaml_plugin_mode=1 \
	    -D "ocaml_plugin_register_provider=$PLUGIN_ID:$PROVIDER_TYPE" \
	    -D ocaml_plugin_load_marker=full1_upstream_plugin_loaded=ok \
	    -D hxhx_backend_plugin_host_runtime=1 \
	    -D ocaml_no_build
) >"$compile_stdout" 2>"$compile_stderr"

dune_exe_name="$(
  awk '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (index(line, "(name ") == 1 || index(line, "(name\t") == 1) {
        gsub(/[()]/, "", line)
        split(line, parts, /[[:space:]]+/)
        print parts[2]
        exit
      }
    }
  ' "$plugin_generated_dir/dune"
)"
if [ -z "$dune_exe_name" ]; then
  echo "full1 plugin upstream-to-hxhx proof: failed to read generated dune executable name" >&2
  exit 1
fi

(
  cd "$plugin_generated_dir"
  dune build "./$dune_exe_name.$artifact_ext"
) >"$build_stdout" 2>"$build_stderr"

generated_artifact="$plugin_generated_dir/_build/default/$dune_exe_name.$artifact_ext"
if [ ! -f "$generated_artifact" ]; then
  echo "full1 plugin upstream-to-hxhx proof: missing generated plugin artifact: $generated_artifact" >&2
  exit 1
fi

plugin_artifact_rel="plugins/$dune_exe_name.$artifact_ext"
plugin_artifact="$plugin_out_dir/$plugin_artifact_rel"
cp "$generated_artifact" "$plugin_artifact"
evidence_plugin_artifact="$ARTIFACT_DIR/verified-plugin-artifact.$artifact_ext"
cp "$plugin_artifact" "$evidence_plugin_artifact"
plugin_artifact_sha256="$(shasum -a 256 "$evidence_plugin_artifact" | awk '{print $1}')"

abi_version="$(read_abi_const VERSION)"
gen_ir_version="$(read_abi_const GEN_IR_VERSION)"
macro_api_version="$(read_abi_const MACRO_API_VERSION)"
manifest_path="$plugin_out_dir/backend-plugin.json"
cat >"$manifest_path" <<EOF
{
  "schemaVersion": 1,
  "pluginId": "$PLUGIN_ID",
  "pluginVersion": "0.1.0",
  "backend": {
    "kind": "ocaml-dynlink",
    "entry": "$plugin_artifact_rel",
    "targetIds": [ "$TARGET_ID" ]
  },
  "requires": {
    "abiVersion": $abi_version,
    "genIrVersion": $gen_ir_version,
    "macroApiVersion": $macro_api_version
  }
}
EOF

set +e
HXHX_FORBID_STAGE0=1 \
  HXHX_TRACE_BACKEND_SELECTION=1 \
  HXHX_TRACE_BACKEND_PROVIDERS=1 \
  "$hxhx_bin" \
    --js "$compile_out_dir/main.js" \
    --hxhx-no-run \
	    -cp "$compile_src_dir" \
	    -main Main \
	    --hxhx-out "$compile_out_dir" \
	    -D "hxhx_backend_plugin_manifest=$manifest_path" \
	  >"$hxhx_stdout" 2>"$hxhx_stderr"
hxhx_status="$?"
set -e
if [ "$hxhx_status" -ne 0 ]; then
  echo "full1 plugin upstream-to-hxhx proof: hxhx compile failed (exit $hxhx_status)" >&2
  cat "$hxhx_stdout" >&2
  cat "$hxhx_stderr" >&2
  exit "$hxhx_status"
fi

if ! grep -q '^full1_upstream_plugin_loaded=ok$' "$hxhx_stdout"; then
	echo "full1 plugin upstream-to-hxhx proof: missing plugin load side-effect marker" >&2
	cat "$hxhx_stdout" >&2
	exit 1
fi
if ! grep -Eq '^backend_plugin_manifest\[[^]]+\]\[[^]]+\]=1$' "$hxhx_stdout"; then
	echo "full1 plugin upstream-to-hxhx proof: manifest did not register exactly one provider" >&2
	cat "$hxhx_stdout" >&2
	exit 1
fi
if ! grep -q '^backend_selected_impl=provider/js-native-wrapper$' "$hxhx_stdout"; then
	echo "full1 plugin upstream-to-hxhx proof: missing backend selection marker" >&2
	cat "$hxhx_stdout" >&2
  exit 1
fi
if [ ! -f "$compile_out_dir/main.js" ]; then
  echo "full1 plugin upstream-to-hxhx proof: missing generated JS output" >&2
  exit 1
fi

node "$compile_out_dir/main.js" >"$node_stdout"
if ! grep -q '^sum=6$' "$node_stdout"; then
  echo "full1 plugin upstream-to-hxhx proof: unexpected generated program output" >&2
  cat "$node_stdout" >&2
  exit 1
fi

ROOT_JSON="$(json_escape "$ROOT")"
TMP_JSON="$(json_escape "$tmp_root")"
HAXE_BIN_JSON="$(json_escape "$haxe_bin")"
HAXE_VERSION_JSON="$(json_escape "$haxe_version")"
DUNE_PATH_JSON="$(json_escape "$dune_path")"
DUNE_VERSION_JSON="$(json_escape "$dune_version")"
OCAMLC_PATH_JSON="$(json_escape "$ocamlc_path")"
OCAMLC_VERSION_JSON="$(json_escape "$ocamlc_version")"
OCAMLOPT_PATH_JSON="$(json_escape "$ocamlopt_path")"
OCAMLOPT_VERSION_JSON="$(json_escape "$ocamlopt_version")"
HXHX_BIN_JSON="$(json_escape "$hxhx_bin")"
MANIFEST_JSON="$(json_escape "$manifest_path")"
ARTIFACT_JSON="$(json_escape "$plugin_artifact")"
COMPILE_OUT_JSON="$(json_escape "$compile_out_dir/main.js")"
CANDIDATE_SHA_JSON="$(json_escape "$CANDIDATE_SHA")"
WORKFLOW_RUN_ID_JSON="$(json_escape "$WORKFLOW_RUN_ID")"
WORKFLOW_RUN_ATTEMPT_JSON="$(json_escape "$WORKFLOW_RUN_ATTEMPT")"

cat >"$summary_json" <<EOF
{
  "schema": "full1-plugin-proof.v1",
  "synthetic": false,
  "route": "upstream-to-hxhx",
  "candidateSha": "$CANDIDATE_SHA_JSON",
  "workflowRun": {
    "id": "$WORKFLOW_RUN_ID_JSON",
    "attempt": "$WORKFLOW_RUN_ATTEMPT_JSON"
  },
  "runId": "$RUN_ID",
  "proof": "reflaxe.ocaml upstream Haxe plugin artifact loaded by hxhx",
  "repoRoot": "$ROOT_JSON",
  "tmpRoot": "$TMP_JSON",
  "hostCompiler": {
    "kind": "upstream-haxe",
    "path": "$HAXE_BIN_JSON",
    "version": "$HAXE_VERSION_JSON"
  },
  "hxhx": {
    "path": "$HXHX_BIN_JSON",
    "stage0Forbidden": true
  },
  "ocamlToolchain": {
    "dunePath": "$DUNE_PATH_JSON",
    "duneVersion": "$DUNE_VERSION_JSON",
    "ocamlcPath": "$OCAMLC_PATH_JSON",
    "ocamlcVersion": "$OCAMLC_VERSION_JSON",
    "ocamloptPath": "$OCAMLOPT_PATH_JSON",
    "ocamloptVersion": "$OCAMLOPT_VERSION_JSON"
  },
  "plugin": {
    "pluginId": "$PLUGIN_ID",
    "targetId": "$TARGET_ID",
    "artifactKind": "ocaml-dynlink",
    "artifactPath": "$ARTIFACT_JSON",
    "artifactSha256": "$plugin_artifact_sha256",
    "evidenceArtifact": "verified-plugin-artifact.$artifact_ext",
    "manifestPath": "$MANIFEST_JSON",
    "loadSideEffect": "full1_upstream_plugin_loaded=ok"
  },
  "sampleCompile": {
    "providerType": "$PROVIDER_TYPE",
    "selectedImpl": "provider/js-native-wrapper",
    "output": "$COMPILE_OUT_JSON",
    "runtimeStdout": "sum=6"
  },
  "logs": {
    "upstreamHaxeStdout": "upstream-haxe.stdout.log",
    "upstreamHaxeStderr": "upstream-haxe.stderr.log",
    "duneStdout": "dune.stdout.log",
    "duneStderr": "dune.stderr.log",
    "hxhxStdout": "hxhx.stdout.log",
    "hxhxStderr": "hxhx.stderr.log",
    "nodeStdout": "node.stdout.log"
  },
  "marker": "REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS",
  "result": "REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS"
}
EOF

echo "full1_plugin_upstream_to_hxhx_summary=$summary_json"
echo "full1_plugin_upstream_to_hxhx_artifact_sha256=$plugin_artifact_sha256"
echo "REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS"
