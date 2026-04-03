#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_SCRIPT="$ROOT/scripts/hxhx/build-backend-plugin.sh"

usage() {
  cat <<'EOF'
Build a native backend plugin artifact from a generated plugin scaffold.

Usage:
  bash scripts/hxhx/plugin-build.sh <scaffold-or-plugin-dir> [--out-dir <dir>]

Accepted inputs:
  <scaffold-or-plugin-dir> may be either:
    - a scaffold root produced by `scripts/hxhx/plugin-init.sh`
    - a direct `plugin/hxhx` source directory containing `backend-plugin.json`

Options:
  --out-dir <dir>   Output directory for built manifest/artifacts.
                    Default: <scaffold>/out when a scaffold root is provided.
  -h, --help        Show this message.
EOF
}

fail() {
  echo "plugin-build: $*" >&2
  exit 1
}

input_dir=""
out_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      out_dir="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail "unknown argument: $1 (use --help)"
      ;;
    *)
      if [ -n "$input_dir" ]; then
        fail "unexpected argument: $1"
      fi
      input_dir="$1"
      shift
      ;;
  esac
done

[ -n "$input_dir" ] || fail "missing scaffold/plugin directory (use --help)"
[ -x "$BUILD_SCRIPT" ] || fail "missing executable build script: $BUILD_SCRIPT"
command -v node >/dev/null 2>&1 || fail "node is required to read plugin manifest metadata"

scaffold_dir=""
plugin_dir=""
manifest_path=""
default_out_dir=""

if [ -f "$input_dir/plugin/hxhx/backend-plugin.json" ]; then
  scaffold_dir="$input_dir"
  plugin_dir="$input_dir/plugin/hxhx"
  manifest_path="$plugin_dir/backend-plugin.json"
  default_out_dir="$scaffold_dir/out"
elif [ -f "$input_dir/backend-plugin.json" ]; then
  plugin_dir="$input_dir"
  manifest_path="$plugin_dir/backend-plugin.json"
else
  fail "could not locate backend-plugin.json under $input_dir"
fi

if [ -z "$out_dir" ]; then
  if [ -n "$default_out_dir" ]; then
    out_dir="$default_out_dir"
  else
    fail "--out-dir is required when building from a direct plugin source dir"
  fi
fi

manifest_fields="$(
  node - "$manifest_path" <<'NODE'
const fs = require('fs')
const manifestPath = process.argv[2]
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
const backend = manifest.backend || {}
const targetIds = Array.isArray(backend.targetIds) ? backend.targetIds : []
console.log([
  manifest.pluginId || '',
  manifest.pluginVersion || '',
  backend.kind || '',
  backend.entry || '',
  targetIds.join(',')
].join('\t'))
NODE
)"
IFS=$'\t' read -r plugin_id plugin_version backend_kind entry_path target_ids_csv <<< "$manifest_fields"

[ -n "$plugin_id" ] || fail "manifest missing pluginId: $manifest_path"
[ -n "$plugin_version" ] || fail "manifest missing pluginVersion: $manifest_path"
[ "$backend_kind" = "ocaml-dynlink" ] || fail "only backend.kind=ocaml-dynlink is supported by plugin-build"
[ -n "$entry_path" ] || fail "manifest missing backend.entry: $manifest_path"
[ -n "$target_ids_csv" ] || fail "manifest missing backend.targetIds: $manifest_path"

dune_target="$(basename "$entry_path")"

build_args=(
  --plugin-id "$plugin_id"
  --plugin-version "$plugin_version"
  --kind "$backend_kind"
  --source-dir "$plugin_dir"
  --dune-target "$dune_target"
  --entry "$entry_path"
  --out-dir "$out_dir"
)

IFS=',' read -r -a target_ids <<< "$target_ids_csv"
for target_id in "${target_ids[@]-}"; do
  [ -n "$target_id" ] || continue
  build_args+=(--target-id "$target_id")
done

bash "$BUILD_SCRIPT" "${build_args[@]}"
