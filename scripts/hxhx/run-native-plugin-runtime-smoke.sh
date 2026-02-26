#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_SCRIPT="$ROOT/scripts/hxhx/build-backend-plugin.sh"
FIXTURE_DIR="$ROOT/test/fixtures/native_backend_plugin"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlopt >/dev/null 2>&1; then
  echo "Skipping native plugin runtime smoke: dune/ocamlopt not found on PATH."
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Skipping native plugin runtime smoke: node not found on PATH."
  exit 0
fi

if [ ! -f "$BUILD_SCRIPT" ]; then
  echo "Missing build script: $BUILD_SCRIPT" >&2
  exit 2
fi

if [ ! -d "$FIXTURE_DIR" ]; then
  echo "Missing native plugin fixture directory: $FIXTURE_DIR" >&2
  exit 2
fi

HXHX_BIN_RESOLVED="${HXHX_BIN:-}"
if [ -z "$HXHX_BIN_RESOLVED" ] || [ ! -x "$HXHX_BIN_RESOLVED" ]; then
  HXHX_NATIVE_PLUGIN_RUNTIME_STAGE0_BUILD="${HXHX_NATIVE_PLUGIN_RUNTIME_STAGE0_BUILD:-1}"
  if [ "$HXHX_NATIVE_PLUGIN_RUNTIME_STAGE0_BUILD" = "1" ]; then
    echo "Building hxhx from source lane for native plugin runtime smoke (HXHX_FORCE_STAGE0=1)..."
    HXHX_FORCE_STAGE0=1 HXHX_STAGE0_HEARTBEAT="${HXHX_STAGE0_HEARTBEAT:-20}" \
      HXHX_STAGE0_FAILFAST_SECS="${HXHX_STAGE0_FAILFAST_SECS:-3600}" \
      HXHX_BIN_RESOLVED="$(bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
  else
    HXHX_BIN_RESOLVED="$(bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
  fi
fi
if [ ! -x "$HXHX_BIN_RESOLVED" ]; then
  echo "Failed to resolve executable hxhx binary: $HXHX_BIN_RESOLVED" >&2
  exit 2
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

plugin_out="$tmp_root/plugin_out"
mkdir -p "$plugin_out"

bash "$BUILD_SCRIPT" \
  --plugin-id fixture.native.backend.plugin \
  --plugin-version 0.1.0 \
  --kind ocaml-cmxs \
  --source-dir "$FIXTURE_DIR" \
  --dune-target hxhx_backend_plugin_fixture.cmxs \
  --entry plugins/hxhx_backend_plugin_fixture.cmxs \
  --target-id js-native \
  --out-dir "$plugin_out"

manifest_rel="$plugin_out/backend-plugin.json"
artifact_rel="$plugin_out/plugins/hxhx_backend_plugin_fixture.cmxs"

if [ ! -f "$manifest_rel" ] || [ ! -f "$artifact_rel" ]; then
  echo "Native plugin build did not produce expected artifacts." >&2
  exit 2
fi

fixture_src="$tmp_root/src"
mkdir -p "$fixture_src"
cat >"$fixture_src/Main.hx" <<'HX'
class Main {
	static function main() {
		var sum = 0;
		for (i in 1...4)
			sum += i;
		Sys.println("sum=" + sum);
	}
}
HX

run_compile_with_manifest() {
  local manifest_path="$1"
  local out_dir="$2"
  mkdir -p "$out_dir"
  HXHX_FORBID_STAGE0=1 \
  HXHX_TRACE_BACKEND_SELECTION=1 \
  HXHX_TRACE_BACKEND_PROVIDERS=1 \
    "$HXHX_BIN_RESOLVED" \
      --target js-native \
      --js "$out_dir/main.js" \
      --hxhx-no-run \
      -cp "$fixture_src" \
      -main Main \
      --hxhx-out "$out_dir" \
      -D "hxhx_backend_provider=backend.js.JsBackend" \
      -D "hxhx_backend_plugin_manifest=$manifest_path" 2>&1
}

out_rel="$tmp_root/out_rel"
compile_rel_output="$(run_compile_with_manifest "$manifest_rel" "$out_rel")"
printf '%s\n' "$compile_rel_output"
printf '%s\n' "$compile_rel_output" | grep -q '^backend_selected_impl=provider/js-native-wrapper$'
node_output_rel="$(node "$out_rel/main.js")"
printf '%s\n' "$node_output_rel"
printf '%s\n' "$node_output_rel" | grep -q '^sum=6$'

manifest_abs="$plugin_out/backend-plugin-absolute.json"
node - "$manifest_rel" "$manifest_abs" "$artifact_rel" <<'NODE'
const fs = require('fs')
const path = require('path')
const [manifestPath, outPath, artifactPath] = process.argv.slice(2)
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
manifest.backend.entry = path.resolve(artifactPath)
fs.writeFileSync(outPath, JSON.stringify(manifest, null, 2) + '\n')
NODE

out_abs="$tmp_root/out_abs"
compile_abs_output="$(run_compile_with_manifest "$manifest_abs" "$out_abs")"
printf '%s\n' "$compile_abs_output"
printf '%s\n' "$compile_abs_output" | grep -q '^backend_selected_impl=provider/js-native-wrapper$'
node_output_abs="$(node "$out_abs/main.js")"
printf '%s\n' "$node_output_abs"
printf '%s\n' "$node_output_abs" | grep -q '^sum=6$'

manifest_missing="$plugin_out/backend-plugin-missing.json"
node - "$manifest_rel" "$manifest_missing" <<'NODE'
const fs = require('fs')
const [manifestPath, outPath] = process.argv.slice(2)
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
manifest.backend.entry = 'plugins/missing.cmxs'
fs.writeFileSync(outPath, JSON.stringify(manifest, null, 2) + '\n')
NODE

set +e
missing_output="$(run_compile_with_manifest "$manifest_missing" "$tmp_root/out_missing" 2>&1)"
missing_code="$?"
set -e
printf '%s\n' "$missing_output"
if [ "$missing_code" -eq 0 ]; then
  echo "Expected missing-entry manifest to fail." >&2
  exit 1
fi
printf '%s\n' "$missing_output" | grep -q "native plugin artifact not found"

manifest_bad_abi="$plugin_out/backend-plugin-bad-abi.json"
node - "$manifest_rel" "$manifest_bad_abi" <<'NODE'
const fs = require('fs')
const [manifestPath, outPath] = process.argv.slice(2)
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
manifest.requires.abiVersion = Number(manifest.requires.abiVersion || 0) + 1
fs.writeFileSync(outPath, JSON.stringify(manifest, null, 2) + '\n')
NODE

set +e
abi_output="$(run_compile_with_manifest "$manifest_bad_abi" "$tmp_root/out_bad_abi" 2>&1)"
abi_code="$?"
set -e
printf '%s\n' "$abi_output"
if [ "$abi_code" -eq 0 ]; then
  echo "Expected ABI-mismatched manifest to fail." >&2
  exit 1
fi
printf '%s\n' "$abi_output" | grep -q "backend ABI mismatch"

echo "plugin_runtime_manifest_relative=$manifest_rel"
echo "plugin_runtime_manifest_absolute=$manifest_abs"
echo "plugin_runtime=ok"
