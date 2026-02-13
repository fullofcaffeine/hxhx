#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/hxhx/hydrate-bootstrap-shards.sh <file-or-dir> [<file-or-dir> ...]

Why:
  Build workflows should stay stage0-free while committed bootstrap snapshots stay below
  large-file thresholds. Sharded snapshots keep large modules split on disk and rehydrate
  them only for local build workspaces.

What:
  - Reads `<Module>.ml.parts` manifests.
  - Concatenates listed `<Module>.ml.partNNN` files into `<Module>.ml`.

Notes:
  - Safe to run repeatedly.
  - For directories, only top-level `*.ml.parts` manifests are considered.
USAGE
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

collect_manifests() {
  local item="$1"
  if [ -d "$item" ]; then
    find "$item" -maxdepth 1 -type f -name '*.ml.parts' -print
  elif [ -f "$item" ]; then
    if [[ "$item" == *.ml.parts ]]; then
      echo "$item"
    fi
  else
    echo "Missing path: $item" >&2
    return 1
  fi
}

hydrate_manifest() {
  local manifest="$1"
  local target dir tmp out_count
  target="${manifest%.parts}"
  dir="$(dirname "$manifest")"
  tmp="$(mktemp "$dir/.hydrate.tmp.XXXXXX")"
  out_count=0

  while IFS= read -r rel_part || [ -n "$rel_part" ]; do
    [ -z "$rel_part" ] && continue
    if [ ! -f "$dir/$rel_part" ]; then
      echo "[hydrate-bootstrap] missing part listed in $(basename "$manifest"): $rel_part" >&2
      rm -f "$tmp"
      return 1
    fi
    cat "$dir/$rel_part" >>"$tmp"
    out_count=$((out_count + 1))
  done <"$manifest"

  if [ "$out_count" -eq 0 ]; then
    echo "[hydrate-bootstrap] empty manifest: $manifest" >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$target"
  echo "[hydrate-bootstrap] hydrated: $target (${out_count} parts)" >&2
}

manifests=()
for item in "$@"; do
  while IFS= read -r path; do
    if [ -n "$path" ]; then
      manifests+=("$path")
    fi
  done <<EOF_MANIFESTS
$(collect_manifests "$item")
EOF_MANIFESTS
done

if [ "${#manifests[@]}" -eq 0 ]; then
  echo "[hydrate-bootstrap] no manifests found" >&2
  exit 0
fi

for manifest in "${manifests[@]}"; do
  hydrate_manifest "$manifest"
done
