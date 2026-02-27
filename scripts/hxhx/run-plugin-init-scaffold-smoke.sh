#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INIT_SCRIPT="$ROOT/scripts/hxhx/plugin-init.sh"
BUILD_SCRIPT="$ROOT/scripts/hxhx/build-backend-plugin.sh"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlopt >/dev/null 2>&1; then
  echo "Skipping plugin init scaffold smoke: dune/ocamlopt not found on PATH."
  exit 0
fi

if [ ! -x "$INIT_SCRIPT" ]; then
  echo "Missing executable plugin init script: $INIT_SCRIPT" >&2
  exit 1
fi

if [ ! -x "$BUILD_SCRIPT" ]; then
  echo "Missing executable build script: $BUILD_SCRIPT" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

scaffold_dir="$tmp_dir/scaffold"
plugin_id="fixture.generated.plugin"
target_name="FixtureJsNative"
target_namespace="fixture.generated"
target_id="js-native"
module_name="fixture_generated_plugin"

bash "$INIT_SCRIPT" \
  --out-dir "$scaffold_dir" \
  --plugin-id "$plugin_id" \
  --plugin-version "0.1.0" \
  --target-name "$target_name" \
  --target-namespace "$target_namespace" \
  --target-id "$target_id"

test -f "$scaffold_dir/plugin/hxhx/backend-plugin.json"
test -f "$scaffold_dir/plugin/hxhx/dune-project"
test -f "$scaffold_dir/plugin/hxhx/dune"
test -f "$scaffold_dir/plugin/hxhx/${module_name}.ml"
test -f "$scaffold_dir/src/fixture/generated/core/FixtureJsNativeCore.hx"
test -f "$scaffold_dir/src/fixture/generated/host/FixtureJsNativeHostHxhx.hx"
test -f "$scaffold_dir/src/fixture/generated/host/FixtureJsNativeHostHaxeEval.hx"
test -f "$scaffold_dir/smoke/Main.hx"
test -f "$scaffold_dir/smoke/build.hxml"

build_out="$tmp_dir/build_out"
bash "$BUILD_SCRIPT" \
  --plugin-id "$plugin_id" \
  --plugin-version "0.1.0" \
  --kind ocaml-cmxs \
  --source-dir "$scaffold_dir/plugin/hxhx" \
  --dune-target "${module_name}.cmxs" \
  --entry "plugins/${module_name}.cmxs" \
  --target-id "$target_id" \
  --out-dir "$build_out"

test -f "$build_out/backend-plugin.json"
test -f "$build_out/plugins/${module_name}.cmxs"

echo "plugin_init_scaffold_path=$scaffold_dir"
echo "plugin_init_build_out=$build_out"
echo "PLUGIN_INIT_SCAFFOLD_SMOKE:PASS"
