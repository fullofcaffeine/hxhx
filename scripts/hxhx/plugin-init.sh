#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ABI_FILE="$ROOT/packages/hxhx-core/src/backend/BackendAbi.hx"

OUT_DIR=""
PLUGIN_ID=""
PLUGIN_VERSION="0.1.0"
TARGET_NAME=""
TARGET_NAMESPACE=""
declare -a TARGET_IDS=()

usage() {
  cat <<'EOF'
Generate a promotion-ready backend plugin scaffold.

Usage:
  bash scripts/hxhx/plugin-init.sh [options]

Required:
  --out-dir <dir>                Output directory for scaffold.
  --plugin-id <id>               Stable plugin identifier.
  --target-id <id>               Target ID provided by this plugin (repeatable).

Optional:
  --plugin-version <version>     Plugin version (default: 0.1.0).
  --target-name <PascalCase>     Target stem used for generated core/adapter class names.
  --target-namespace <a.b.c>     Namespace for generated Haxe modules.
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
  echo "plugin-init: $*" >&2
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

to_pascal_case() {
  local raw="$1"
  local sanitized
  sanitized="$(echo "$raw" | sed -E 's/[^A-Za-z0-9]+/ /g')"
  local word
  local out=""
  for word in $sanitized; do
    local head="${word:0:1}"
    local tail="${word:1}"
    head="$(printf '%s' "$head" | tr '[:lower:]' '[:upper:]')"
    out+="${head}${tail}"
  done
  if [ -z "$out" ]; then
    out="GeneratedTarget"
  fi
  if [[ "$out" =~ ^[0-9] ]]; then
    out="_${out}"
  fi
  printf '%s' "$out"
}

normalize_namespace() {
  local raw="$1"
  local sanitized
  sanitized="$(echo "$raw" | sed -E 's/[^A-Za-z0-9.]+/./g; s/\.+/./g; s/^\.//; s/\.$//')"
  if [ -z "$sanitized" ]; then
    sanitized="generated.plugin"
  fi
  local -a segments=()
  local segment
  IFS='.' read -r -a segments <<< "$sanitized"
  local out=""
  for segment in "${segments[@]}"; do
    segment="$(echo "$segment" | sed -E 's/[^A-Za-z0-9_]+/_/g')"
    if [ -z "$segment" ]; then
      continue
    fi
    if [[ "$segment" =~ ^[0-9] ]]; then
      segment="_${segment}"
    fi
    segment="$(printf '%s' "$segment" | tr 'A-Z' 'a-z')"
    if [ -n "$out" ]; then
      out="${out}.${segment}"
    else
      out="$segment"
    fi
  done
  if [ -z "$out" ]; then
    out="generated.plugin"
  fi
  printf '%s' "$out"
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
[ -f "$ABI_FILE" ] || fail "missing ABI constants file: $ABI_FILE"

safe_token_or_fail "$PLUGIN_ID" "plugin id"
safe_token_or_fail "$PLUGIN_VERSION" "plugin version"
for target_id in "${TARGET_IDS[@]-}"; do
  safe_token_or_fail "$target_id" "target id"
done

if [ -z "$TARGET_NAME" ]; then
  TARGET_NAME="$(to_pascal_case "$PLUGIN_ID")"
fi
if [[ ! "$TARGET_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  fail "--target-name must match [A-Za-z_][A-Za-z0-9_]*"
fi

if [ -z "$TARGET_NAMESPACE" ]; then
  TARGET_NAMESPACE="$PLUGIN_ID"
fi
TARGET_NAMESPACE="$(normalize_namespace "$TARGET_NAMESPACE")"

module_name="$(echo "$PLUGIN_ID" | sed -E 's/[^A-Za-z0-9]+/_/g' | sed -E 's/^_+//; s/_+$//' | tr 'A-Z' 'a-z')"
if [ -z "$module_name" ]; then
  module_name="generated_plugin"
fi
if [[ "$module_name" =~ ^[0-9] ]]; then
  module_name="_${module_name}"
fi

ABI_VERSION="$(read_abi_const VERSION)"
GEN_IR_VERSION="$(read_abi_const GEN_IR_VERSION)"
MACRO_API_VERSION="$(read_abi_const MACRO_API_VERSION)"

target_ids_json=""
for target_id in "${TARGET_IDS[@]-}"; do
  if [ -n "$target_ids_json" ]; then
    target_ids_json="$target_ids_json, "
  fi
  target_ids_json="$target_ids_json\"$target_id\""
done

namespace_path="$(printf '%s' "$TARGET_NAMESPACE" | tr '.' '/')"
core_dir="$OUT_DIR/src/$namespace_path/core"
host_dir="$OUT_DIR/src/$namespace_path/host"
plugin_dir="$OUT_DIR/plugin/hxhx"
smoke_dir="$OUT_DIR/smoke"
mkdir -p "$core_dir" "$host_dir" "$plugin_dir" "$smoke_dir"

cat > "$core_dir/${TARGET_NAME}Core.hx" <<EOF
package ${TARGET_NAMESPACE}.core;

/**
	Promotion target-core placeholder.
	Move all target codegen logic into this class so host adapters remain thin wrappers.
**/
class ${TARGET_NAME}Core {
	public function new() {}
}
EOF

cat > "$host_dir/${TARGET_NAME}HostHxhx.hx" <<EOF
package ${TARGET_NAMESPACE}.host;

/**
	hxhx Stage3 backend plugin host adapter placeholder.
	Keep Stage3 ABI glue here; keep codegen inside ${TARGET_NAMESPACE}.core.${TARGET_NAME}Core.
**/
class ${TARGET_NAME}HostHxhx {
	public static inline final PLUGIN_ID = "${PLUGIN_ID}";
	public static inline final PROVIDER_TYPE = "${TARGET_NAMESPACE}.host.${TARGET_NAME}HostHxhx";
}
EOF

cat > "$host_dir/${TARGET_NAME}HostHaxeEval.hx" <<EOF
package ${TARGET_NAMESPACE}.host;

/**
	Upstream eval host adapter placeholder.
	This lane is loaded via eval.vm.Context.loadPlugin and should only contain eval-host glue.
**/
class ${TARGET_NAME}HostHaxeEval {
	public static inline final LOAD_PLUGIN_API = "eval.vm.Context.loadPlugin";
}
EOF

cat > "$plugin_dir/dune-project" <<EOF
(lang dune 3.11)

(name ${module_name})
EOF

cat > "$plugin_dir/dune" <<EOF
(library
 (name ${module_name})
 (modules ${module_name})
 (modes native byte))
EOF

cat > "$plugin_dir/${module_name}.ml" <<EOF
let plugin_id : string = "${PLUGIN_ID}"

let register () : unit = ()
EOF

cat > "$plugin_dir/backend-plugin.json" <<EOF
{
  "schemaVersion": 1,
  "pluginId": "${PLUGIN_ID}",
  "pluginVersion": "${PLUGIN_VERSION}",
  "backend": {
    "kind": "ocaml-dynlink",
    "entry": "plugins/${module_name}.cmxs",
    "targetIds": [ ${target_ids_json} ]
  },
  "requires": {
    "abiVersion": ${ABI_VERSION},
    "genIrVersion": ${GEN_IR_VERSION},
    "macroApiVersion": ${MACRO_API_VERSION}
  }
}
EOF

cat > "$smoke_dir/Main.hx" <<'EOF'
class Main {
	static function main() {
		var sum = 0;
		for (i in 1...4)
			sum += i;
		Sys.println("sum=" + sum);
	}
}
EOF

cat > "$smoke_dir/build.hxml" <<'EOF'
-cp .
-main Main
--interp
EOF

cat > "$OUT_DIR/README.md" <<EOF
# Promotion Scaffold

Generated by \`scripts/hxhx/plugin-init.sh\`.

## Build native plugin artifact

\`\`\`bash
hxhx plugin build ${OUT_DIR} \\
  --out-dir ${OUT_DIR}/out
\`\`\`

## Validate scaffold output

\`\`\`bash
hxhx plugin test ${OUT_DIR} \\
  --out-dir ${OUT_DIR}/out
\`\`\`

Next steps:

1. Implement target logic in \`src/${namespace_path}/core/${TARGET_NAME}Core.hx\`.
2. Implement host glue in \`src/${namespace_path}/host/${TARGET_NAME}HostHxhx.hx\` and \`HostHaxeEval.hx\`.
3. Replace \`plugin/hxhx/${module_name}.ml\` placeholder registration with real provider registration side effects.
EOF

echo "plugin_init_out=$OUT_DIR"
echo "plugin_init_module_name=$module_name"
echo "plugin_init_target_name=$TARGET_NAME"
echo "plugin_init_namespace=$TARGET_NAMESPACE"
echo "plugin_init=ok"
