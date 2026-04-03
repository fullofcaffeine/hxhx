#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_WRAPPER="$ROOT/scripts/hxhx/plugin-build.sh"
MANIFEST_NAME="backend-plugin.json"

usage() {
  cat <<'EOF'
Validate a generated native plugin scaffold by building its manifest/artifact outputs.

Usage:
  bash scripts/hxhx/plugin-test.sh <scaffold-or-plugin-dir> [--out-dir <dir>]

Options:
  --out-dir <dir>   Output directory forwarded to plugin-build.
  -h, --help        Show this message.
EOF
}

fail() {
  echo "plugin-test: $*" >&2
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
[ -x "$BUILD_WRAPPER" ] || fail "missing executable plugin-build wrapper: $BUILD_WRAPPER"

existing_out_dir=""
if [ -f "$input_dir/plugin/hxhx/backend-plugin.json" ]; then
  [ -f "$input_dir/plugin/hxhx/dune-project" ] || fail "missing dune-project in scaffold plugin dir"
  [ -f "$input_dir/plugin/hxhx/dune" ] || fail "missing dune file in scaffold plugin dir"
  [ -f "$input_dir/smoke/Main.hx" ] || fail "missing scaffold smoke Main.hx"
  [ -f "$input_dir/smoke/build.hxml" ] || fail "missing scaffold smoke build.hxml"
  existing_out_dir="${out_dir:-$input_dir/out}"
elif [ -n "$out_dir" ]; then
  existing_out_dir="$out_dir"
fi

manifest_path=""
artifact_path=""

if [ -n "$existing_out_dir" ] && [ -f "$existing_out_dir/$MANIFEST_NAME" ]; then
  manifest_path="$existing_out_dir/$MANIFEST_NAME"
  manifest_fields="$(
    node - "$manifest_path" <<'NODE'
const fs = require('fs')
const manifestPath = process.argv[2]
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
const backend = manifest.backend || {}
console.log([
  backend.kind || '',
  backend.entry || ''
].join('\t'))
NODE
  )"
  IFS=$'\t' read -r backend_kind backend_entry <<< "$manifest_fields"
  if [ "$backend_kind" = "ocaml-dynlink" ]; then
    [ -n "$backend_entry" ] || fail "built manifest missing backend.entry: $manifest_path"
    artifact_path="$existing_out_dir/$backend_entry"
  fi
else
  build_output="$(
    if [ -n "$out_dir" ]; then
      bash "$BUILD_WRAPPER" "$input_dir" --out-dir "$out_dir"
    else
      bash "$BUILD_WRAPPER" "$input_dir"
    fi
  )"
  printf '%s\n' "$build_output"

  manifest_path="$(printf '%s\n' "$build_output" | awk -F= '/^plugin_manifest=/{print substr($0, index($0, "=")+1)}' | tail -n 1)"
  artifact_path="$(printf '%s\n' "$build_output" | awk -F= '/^plugin_cmxs=/{print substr($0, index($0, "=")+1)}' | tail -n 1)"
fi

[ -n "$manifest_path" ] || fail "plugin-build did not emit plugin_manifest marker"
[ -f "$manifest_path" ] || fail "built manifest missing: $manifest_path"

if [ -n "$artifact_path" ]; then
  [ -f "$artifact_path" ] || fail "built artifact missing: $artifact_path"
fi

echo "plugin_test_manifest=$manifest_path"
if [ -n "$artifact_path" ]; then
  echo "plugin_test_artifact=$artifact_path"
fi
echo "plugin_test=ok"
