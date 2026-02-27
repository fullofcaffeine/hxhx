#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INIT_SCRIPT="$ROOT/scripts/hxhx/plugin-init.sh"
BUILD_SCRIPT="$ROOT/scripts/hxhx/build-backend-plugin.sh"

OUT_DIR=""
PLUGIN_ID=""
PLUGIN_VERSION="0.1.0"
PROVIDER_TYPE=""
TARGET_NAME=""
TARGET_NAMESPACE=""
ARTIFACT_EXT="cmxs"
declare -a TARGET_IDS=()

usage() {
  cat <<'EOF'
Promote a backend provider type into a runtime-loadable native plugin artifact.

Usage:
  bash scripts/hxhx/promote-backend-plugin.sh [options]

Required:
  --out-dir <dir>                Output directory.
  --plugin-id <id>               Stable plugin identifier.
  --provider-type <type.path>    Haxe provider type (e.g. backend.js.JsBackend).
  --target-id <id>               Target ID provided by this plugin (repeatable).

Optional:
  --plugin-version <version>     Plugin version (default: 0.1.0).
  --target-name <PascalCase>     Forwarded to plugin scaffold generator.
  --target-namespace <a.b.c>     Forwarded to plugin scaffold generator.
  --artifact-ext <cmxs|cma>      Artifact extension (default: cmxs).
  --target-ids <csv>             Comma-separated target IDs.
  -h, --help                     Show this message.
EOF
}

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

fail() {
  echo "promote-backend-plugin: $*" >&2
  exit 1
}

safe_token_or_fail() {
  local value="$1"
  local label="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._/@:+-]+$ ]]; then
    fail "$label contains unsupported characters: $value"
  fi
}

append_target_ids() {
  local raw="${1:-}"
  local -a parts=()
  local normalized
  local existing
  IFS=',;' read -r -a parts <<< "$raw" || true
  for normalized in "${parts[@]-}"; do
    normalized="$(trim "$normalized")"
    if [ -z "$normalized" ]; then
      continue
    fi
    existing=0
    for current in "${TARGET_IDS[@]-}"; do
      if [ "$current" = "$normalized" ]; then
        existing=1
        break
      fi
    done
    if [ "$existing" -eq 0 ]; then
      TARGET_IDS+=("$normalized")
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="$(trim "${2:-}")"
      shift 2
      ;;
    --plugin-id)
      PLUGIN_ID="$(trim "${2:-}")"
      shift 2
      ;;
    --plugin-version)
      PLUGIN_VERSION="$(trim "${2:-}")"
      shift 2
      ;;
    --provider-type)
      PROVIDER_TYPE="$(trim "${2:-}")"
      shift 2
      ;;
    --target-name)
      TARGET_NAME="$(trim "${2:-}")"
      shift 2
      ;;
    --target-namespace)
      TARGET_NAMESPACE="$(trim "${2:-}")"
      shift 2
      ;;
    --artifact-ext)
      ARTIFACT_EXT="$(trim "${2:-}")"
      shift 2
      ;;
    --target-id)
      append_target_ids "${2:-}"
      shift 2
      ;;
    --target-ids)
      append_target_ids "${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1 (use --help)"
      ;;
  esac
done

[ -n "$OUT_DIR" ] || fail "--out-dir is required"
[ -n "$PLUGIN_ID" ] || fail "--plugin-id is required"
[ -n "$PROVIDER_TYPE" ] || fail "--provider-type is required"
target_count=0
for _target in "${TARGET_IDS[@]-}"; do
  if [ -n "$_target" ]; then
    target_count=$((target_count + 1))
  fi
done
[ "$target_count" -gt 0 ] || fail "at least one --target-id is required"

[ -x "$INIT_SCRIPT" ] || fail "missing executable scaffold script: $INIT_SCRIPT"
[ -x "$BUILD_SCRIPT" ] || fail "missing executable build script: $BUILD_SCRIPT"

safe_token_or_fail "$PLUGIN_ID" "plugin id"
safe_token_or_fail "$PLUGIN_VERSION" "plugin version"
for target_id in "${TARGET_IDS[@]-}"; do
  safe_token_or_fail "$target_id" "target id"
done

if [[ ! "$PROVIDER_TYPE" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]]; then
  fail "--provider-type must be a valid type path"
fi

case "$ARTIFACT_EXT" in
  cmxs|cma) ;;
  *)
    fail "--artifact-ext must be cmxs or cma"
    ;;
esac

module_name="$(echo "$PLUGIN_ID" | sed -E 's/[^A-Za-z0-9]+/_/g' | sed -E 's/^_+//; s/_+$//' | tr 'A-Z' 'a-z')"
if [ -z "$module_name" ]; then
  module_name="generated_plugin"
fi
if [[ "$module_name" =~ ^[0-9] ]]; then
  module_name="_${module_name}"
fi

mkdir -p "$OUT_DIR"
scaffold_dir="$OUT_DIR/scaffold"

init_args=(
  --out-dir "$scaffold_dir"
  --plugin-id "$PLUGIN_ID"
  --plugin-version "$PLUGIN_VERSION"
)
if [ -n "$TARGET_NAME" ]; then
  init_args+=(--target-name "$TARGET_NAME")
fi
if [ -n "$TARGET_NAMESPACE" ]; then
  init_args+=(--target-namespace "$TARGET_NAMESPACE")
fi
for target_id in "${TARGET_IDS[@]-}"; do
  init_args+=(--target-id "$target_id")
done

bash "$INIT_SCRIPT" "${init_args[@]}"

plugin_ml="$scaffold_dir/plugin/hxhx/${module_name}.ml"
if [ ! -f "$plugin_ml" ]; then
  fail "expected scaffold module not found: $plugin_ml"
fi

cat > "$plugin_ml" <<EOF
let plugin_id : string = "${PLUGIN_ID}"
let provider_type : string = "${PROVIDER_TYPE}"

let register () : unit = ()

let () = register ()
EOF

build_args=(
  --plugin-id "$PLUGIN_ID"
  --plugin-version "$PLUGIN_VERSION"
  --kind ocaml-cmxs
  --source-dir "$scaffold_dir/plugin/hxhx"
  --dune-target "${module_name}.${ARTIFACT_EXT}"
  --entry "plugins/${module_name}.${ARTIFACT_EXT}"
  --out-dir "$OUT_DIR"
)
for target_id in "${TARGET_IDS[@]-}"; do
  build_args+=(--target-id "$target_id")
done

bash "$BUILD_SCRIPT" "${build_args[@]}"

echo "promotion_scaffold=$scaffold_dir"
echo "promotion_provider_type=$PROVIDER_TYPE"
echo "promotion_plugin_manifest=$OUT_DIR/backend-plugin.json"
echo "promotion_plugin_artifact=$OUT_DIR/plugins/${module_name}.${ARTIFACT_EXT}"
echo "promotion_backend=ok"
