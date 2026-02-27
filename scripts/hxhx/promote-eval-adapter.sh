#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INIT_SCRIPT="$ROOT/scripts/hxhx/plugin-init.sh"

OUT_DIR=""
PLUGIN_ID=""
PLUGIN_VERSION="0.1.0"
TARGET_NAME=""
TARGET_NAMESPACE=""
ARTIFACT_EXT="cmxs"
declare -a TARGET_IDS=()

usage() {
  cat <<'EOF'
Promote a target scaffold into an upstream eval-plugin native adapter artifact.

Usage:
  bash scripts/hxhx/promote-eval-adapter.sh [options]

Required:
  --out-dir <dir>                Output directory.
  --plugin-id <id>               Stable plugin identifier.
  --target-id <id>               Target ID used by scaffold generation (repeatable).

Optional:
  --plugin-version <version>     Plugin version (default: 0.1.0).
  --target-name <PascalCase>     Forwarded to scaffold generator.
  --target-namespace <a.b.c>     Forwarded to scaffold generator.
  --artifact-ext <cmxs|cma>      Adapter artifact extension (default: cmxs).
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
  echo "promote-eval-adapter: $*" >&2
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
target_count=0
for _target in "${TARGET_IDS[@]-}"; do
  if [ -n "$_target" ]; then
    target_count=$((target_count + 1))
  fi
done
[ "$target_count" -gt 0 ] || fail "at least one --target-id is required"

[ -x "$INIT_SCRIPT" ] || fail "missing executable scaffold script: $INIT_SCRIPT"
command -v dune >/dev/null 2>&1 || fail "dune is required"
command -v ocamlopt >/dev/null 2>&1 || fail "ocamlopt is required"

safe_token_or_fail "$PLUGIN_ID" "plugin id"
safe_token_or_fail "$PLUGIN_VERSION" "plugin version"
for target_id in "${TARGET_IDS[@]-}"; do
  safe_token_or_fail "$target_id" "target id"
done

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
eval_module="${module_name}_eval"

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

eval_dir="$scaffold_dir/plugin/haxe_eval"
mkdir -p "$eval_dir"

cat > "$eval_dir/dune-project" <<EOF
(lang dune 3.11)

(name ${eval_module})
EOF

cat > "$eval_dir/dune" <<EOF
(library
 (name ${eval_module})
 (modules ${eval_module})
 (modes native byte))
EOF

cat > "$eval_dir/${eval_module}.ml" <<EOF
let plugin_id : string = "${PLUGIN_ID}"
let host_kind : string = "haxe-eval"

let register () : unit = ()

let () = register ()
EOF

dune_build_dir="$OUT_DIR/.dune-build-eval"
rm -rf "$dune_build_dir"
(
  cd "$eval_dir"
  dune build --build-dir "$dune_build_dir" "${eval_module}.${ARTIFACT_EXT}"
)

local_artifact="$dune_build_dir/default/${eval_module}.${ARTIFACT_EXT}"
[ -f "$local_artifact" ] || fail "dune did not produce expected eval artifact: $local_artifact"

artifact_output="$OUT_DIR/plugins/${eval_module}.${ARTIFACT_EXT}"
mkdir -p "$(dirname "$artifact_output")"
cp "$local_artifact" "$artifact_output"
rm -rf "$dune_build_dir"

manifest_path="$OUT_DIR/eval-plugin.json"
cat > "$manifest_path" <<EOF
{
  "schemaVersion": 1,
  "pluginId": "$PLUGIN_ID",
  "pluginVersion": "$PLUGIN_VERSION",
  "host": {
    "kind": "haxe-eval",
    "entry": "plugins/${eval_module}.${ARTIFACT_EXT}",
    "loadApi": "eval.vm.Context.loadPlugin"
  },
  "compatibilityLevel": 1,
  "crossHostBinaryCompatibility": false
}
EOF

echo "promotion_scaffold=$scaffold_dir"
echo "promotion_eval_manifest=$manifest_path"
echo "promotion_eval_artifact=$artifact_output"
echo "promotion_eval=ok"
