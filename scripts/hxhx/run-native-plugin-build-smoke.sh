#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_SCRIPT="$ROOT/scripts/hxhx/build-backend-plugin.sh"
FIXTURE_DIR="$ROOT/test/fixtures/native_backend_plugin"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlopt >/dev/null 2>&1; then
  echo "Skipping native plugin build smoke: dune/ocamlopt not found on PATH."
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Missing node on PATH (required to validate generated manifest)." >&2
  exit 1
fi

if [ ! -x "$BUILD_SCRIPT" ]; then
  echo "Missing executable build script: $BUILD_SCRIPT" >&2
  exit 1
fi

if [ ! -d "$FIXTURE_DIR" ]; then
  echo "Missing native plugin fixture directory: $FIXTURE_DIR" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

out_dir="$tmp_dir/out"
manifest_path="$out_dir/backend-plugin.json"
artifact_rel="plugins/hxhx_backend_plugin_fixture.cmxs"
artifact_path="$out_dir/$artifact_rel"

bash "$BUILD_SCRIPT" \
  --plugin-id fixture.native.backend.plugin \
  --plugin-version 0.1.0 \
  --kind ocaml-cmxs \
  --source-dir "$FIXTURE_DIR" \
  --dune-target hxhx_backend_plugin_fixture.cmxs \
  --entry "$artifact_rel" \
  --target-id js-native \
  --out-dir "$out_dir"

test -f "$manifest_path"
test -f "$artifact_path"

node - "$manifest_path" "$artifact_rel" <<'NODE'
const fs = require('fs')
const manifestPath = process.argv[2]
const expectedEntry = process.argv[3]
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
if (manifest.schemaVersion !== 1) {
  throw new Error(`unexpected schemaVersion: ${manifest.schemaVersion}`)
}
if (manifest.pluginId !== 'fixture.native.backend.plugin') {
  throw new Error(`unexpected pluginId: ${manifest.pluginId}`)
}
if (manifest.backend?.kind !== 'ocaml-cmxs') {
  throw new Error(`unexpected backend.kind: ${manifest.backend?.kind}`)
}
if (manifest.backend?.entry !== expectedEntry) {
  throw new Error(`unexpected backend.entry: ${manifest.backend?.entry}`)
}
if (!Array.isArray(manifest.backend?.targetIds) || manifest.backend.targetIds.length !== 1 || manifest.backend.targetIds[0] !== 'js-native') {
  throw new Error(`unexpected backend.targetIds: ${JSON.stringify(manifest.backend?.targetIds)}`)
}
if (manifest.requires?.abiVersion !== 1 || manifest.requires?.genIrVersion !== 1 || manifest.requires?.macroApiVersion !== 1) {
  throw new Error(`unexpected requires block: ${JSON.stringify(manifest.requires)}`)
}
NODE

echo "plugin_build_manifest=$manifest_path"
echo "plugin_build_artifact=$artifact_path"
echo "NATIVE_PLUGIN_BUILD_SMOKE:PASS"
