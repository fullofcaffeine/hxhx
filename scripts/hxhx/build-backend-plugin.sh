#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ABI_FILE="$ROOT/packages/hxhx-core/src/backend/BackendAbi.hx"

PLUGIN_ID=""
PLUGIN_VERSION=""
KIND="ocaml-dynlink"
ENTRY=""
OUT_DIR=""
SOURCE_DIR=""
DUNE_TARGET=""
MANIFEST_NAME="backend-plugin.json"
declare -a TARGET_IDS=()

usage() {
  cat <<'EOF'
Build native backend plugin artifacts and emit a compatible manifest.

Usage:
  bash scripts/hxhx/build-backend-plugin.sh [options]

Required:
  --plugin-id <id>               Stable plugin identifier.
  --plugin-version <version>     Plugin release/version string.
  --target-id <id>               Target ID provided by this plugin (repeatable).
  --out-dir <dir>                Output directory for manifest/artifacts.

Optional:
  --kind <linked-provider|ocaml-dynlink> Manifest runtime kind (default: ocaml-dynlink).
  --entry <value>                Provider type path (linked-provider) or output
                                 artifact path relative to --out-dir (ocaml-dynlink).
  --source-dir <dir>             OCaml plugin source directory (required for ocaml-dynlink).
  --dune-target <file.cmxs>      Dune build target inside --source-dir.
                                 Default: basename of --entry, else backend_plugin.cmxs.
  --manifest-name <file.json>    Manifest filename (default: backend-plugin.json).
  -h, --help                     Show this message.

Examples:
  # Build native .cmxs from a dune package
  bash scripts/hxhx/build-backend-plugin.sh \
    --plugin-id demo.native \
    --plugin-version 0.1.0 \
    --kind ocaml-dynlink \
    --source-dir test/fixtures/native_backend_plugin \
    --dune-target hxhx_backend_plugin_fixture.cmxs \
    --entry plugins/hxhx_backend_plugin_fixture.cmxs \
    --target-id js-native \
    --out-dir .tmp/plugin-out

  # Emit manifest-only declaration for a linked provider class
  bash scripts/hxhx/build-backend-plugin.sh \
    --plugin-id demo.haxe \
    --plugin-version 0.1.0 \
    --kind linked-provider \
    --entry my.backend.Provider \
    --target-id js-native \
    --out-dir .tmp/plugin-out
EOF
}

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

fail() {
  echo "build-backend-plugin: $*" >&2
  exit 1
}

append_target_ids() {
  local raw="${1:-}"
  local -a parts=()
  local normalized
  local item
  local existing
  IFS=',;' read -r -a parts <<< "$raw" || true
  for item in "${parts[@]-}"; do
    normalized="$(trim "$item")"
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

safe_token_or_fail() {
  local value="$1"
  local label="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._/@:+-]+$ ]]; then
    fail "$label contains unsupported characters: $value"
  fi
}

read_abi_const() {
  local name="$1"
  local value
  value="$(grep -E "public[[:space:]]+static[[:space:]]+inline[[:space:]]+var[[:space:]]+$name:Int[[:space:]]*=" "$ABI_FILE" | head -n 1 | sed -E 's/.*=[[:space:]]*([0-9]+).*/\1/')"
  if [ -z "$value" ]; then
    fail "failed to read $name from $ABI_FILE"
  fi
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-id)
      PLUGIN_ID="$(trim "${2:-}")"
      shift 2
      ;;
    --plugin-version)
      PLUGIN_VERSION="$(trim "${2:-}")"
      shift 2
      ;;
    --kind)
      KIND="$(trim "${2:-}")"
      shift 2
      ;;
    --entry)
      ENTRY="$(trim "${2:-}")"
      shift 2
      ;;
    --source-dir)
      SOURCE_DIR="$(trim "${2:-}")"
      shift 2
      ;;
    --dune-target)
      DUNE_TARGET="$(trim "${2:-}")"
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
    --out-dir)
      OUT_DIR="$(trim "${2:-}")"
      shift 2
      ;;
    --manifest-name)
      MANIFEST_NAME="$(trim "${2:-}")"
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

[ -n "$PLUGIN_ID" ] || fail "--plugin-id is required"
[ -n "$PLUGIN_VERSION" ] || fail "--plugin-version is required"
[ -n "$OUT_DIR" ] || fail "--out-dir is required"
target_count=0
for _target in "${TARGET_IDS[@]-}"; do
  if [ -n "$_target" ]; then
    target_count=$((target_count + 1))
  fi
done
[ "$target_count" -gt 0 ] || fail "at least one --target-id is required"
[ -f "$ABI_FILE" ] || fail "missing ABI constants file: $ABI_FILE"

case "$KIND" in
  linked-provider|ocaml-dynlink) ;;
  *)
    fail "--kind must be one of: linked-provider, ocaml-dynlink"
    ;;
esac

safe_token_or_fail "$PLUGIN_ID" "plugin id"
safe_token_or_fail "$PLUGIN_VERSION" "plugin version"
for target_id in "${TARGET_IDS[@]-}"; do
  safe_token_or_fail "$target_id" "target id"
done

ABI_VERSION="$(read_abi_const VERSION)"
GEN_IR_VERSION="$(read_abi_const GEN_IR_VERSION)"
MACRO_API_VERSION="$(read_abi_const MACRO_API_VERSION)"

mkdir -p "$OUT_DIR"

artifact_output=""
manifest_entry="$ENTRY"

if [ "$KIND" = "linked-provider" ]; then
  [ -n "$manifest_entry" ] || fail "--entry is required for --kind linked-provider"
  safe_token_or_fail "$manifest_entry" "linked-provider entry"
else
  [ -n "$SOURCE_DIR" ] || fail "--source-dir is required for --kind ocaml-dynlink"
  [ -d "$SOURCE_DIR" ] || fail "source directory not found: $SOURCE_DIR"
  command -v dune >/dev/null 2>&1 || fail "dune is required for --kind ocaml-dynlink"
  command -v ocamlopt >/dev/null 2>&1 || fail "ocamlopt is required for --kind ocaml-dynlink"

  if [ -z "$DUNE_TARGET" ]; then
    if [ -n "$manifest_entry" ]; then
      DUNE_TARGET="$(basename "$manifest_entry")"
    else
      DUNE_TARGET="backend_plugin.cmxs"
    fi
  fi
  if [[ ! "$DUNE_TARGET" =~ \.(cmxs|cma)$ ]]; then
    fail "--dune-target must end with .cmxs or .cma"
  fi

  dune_build_dir="$OUT_DIR/.dune-build"
  rm -rf "$dune_build_dir"
  (
    cd "$SOURCE_DIR"
    dune build --build-dir "$dune_build_dir" "$DUNE_TARGET"
  )

  local_artifact="$dune_build_dir/default/$DUNE_TARGET"
  [ -f "$local_artifact" ] || fail "dune target did not produce expected artifact: $local_artifact"

  if [ -z "$manifest_entry" ]; then
    manifest_entry="$DUNE_TARGET"
  fi
  if [[ ! "$manifest_entry" =~ \.(cmxs|cma)$ ]]; then
    fail "--entry must end with .cmxs or .cma for --kind ocaml-dynlink"
  fi

  artifact_output="$OUT_DIR/$manifest_entry"
  mkdir -p "$(dirname "$artifact_output")"
  cp "$local_artifact" "$artifact_output"
  rm -rf "$dune_build_dir"
fi

target_ids_json=""
for target_id in "${TARGET_IDS[@]-}"; do
  if [ -n "$target_ids_json" ]; then
    target_ids_json="$target_ids_json, "
  fi
  target_ids_json="$target_ids_json\"$target_id\""
done

manifest_path="$OUT_DIR/$MANIFEST_NAME"
cat > "$manifest_path" <<EOF
{
  "schemaVersion": 1,
  "pluginId": "$PLUGIN_ID",
  "pluginVersion": "$PLUGIN_VERSION",
  "backend": {
    "kind": "$KIND",
    "entry": "$manifest_entry",
    "targetIds": [ $target_ids_json ]
  },
  "requires": {
    "abiVersion": $ABI_VERSION,
    "genIrVersion": $GEN_IR_VERSION,
    "macroApiVersion": $MACRO_API_VERSION
  }
}
EOF

echo "plugin_manifest=$manifest_path"
if [ -n "$artifact_output" ]; then
  echo "plugin_cmxs=$artifact_output"
fi
echo "plugin_build=ok"
