#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/hxhx/shard-bootstrap-ml.sh [--max-bytes <n>] <file-or-dir> [<file-or-dir> ...]

Why:
  Keep generated bootstrap OCaml units below GitHub warning thresholds without
  changing stage0-free build behavior.

What:
  - For each target .ml file larger than --max-bytes (default: 50000000), split
    it into `<File>.partNNN` chunks and emit a `<File>.parts` manifest.
  - Replace the original file with a tiny placeholder comment.
  - Rehydrate the real .ml using scripts/hxhx/hydrate-bootstrap-shards.sh before dune builds.

Notes:
  - Safe to run repeatedly (idempotent).
  - For directories, only top-level '*.ml' files are considered (excluding shard chunks).
USAGE
}

MAX_BYTES="${HXHX_BOOTSTRAP_SHARD_MAX_BYTES:-50000000}"

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "${1:-}" = "--max-bytes" ]; then
  if [ "$#" -lt 3 ]; then
    echo "Missing value or paths for --max-bytes" >&2
    exit 1
  fi
  MAX_BYTES="$2"
  shift 2
fi

case "$MAX_BYTES" in
  ''|*[!0-9]*)
    echo "Invalid --max-bytes value: $MAX_BYTES" >&2
    exit 1
    ;;
esac
if [ "$MAX_BYTES" -lt 1024 ]; then
  echo "Invalid --max-bytes value: $MAX_BYTES" >&2
  exit 1
fi

collect_targets() {
  local item="$1"
  if [ -d "$item" ]; then
    find "$item" -maxdepth 1 -type f -name '*.ml' ! -name '*.ml.part*' -print
  elif [ -f "$item" ]; then
    echo "$item"
  else
    echo "Missing path: $item" >&2
    return 1
  fi
}

file_size_bytes() {
  local path="$1"
  if stat -f %z "$path" >/dev/null 2>&1; then
    stat -f %z "$path"
  else
    stat -c %s "$path"
  fi
}

cleanup_legacy_parts() {
  local dir="$1"
  local base="$2"
  local stem="${base%.ml}"
  find "$dir" -maxdepth 1 -type f -name "${stem}_part*.ml" -delete >/dev/null 2>&1 || true
}

shard_file() {
  local target="$1"
  local dir base size manifest chunk_count tmp_dir idx

  dir="$(dirname "$target")"
  base="$(basename "$target")"
  manifest="$target.parts"

  if [ -f "$manifest" ]; then
    local missing=0
    while IFS= read -r rel_part || [ -n "$rel_part" ]; do
      [ -z "$rel_part" ] && continue
      if [ ! -f "$dir/$rel_part" ]; then
        echo "[shard-bootstrap] missing shard part listed in $manifest: $rel_part" >&2
        missing=1
      fi
    done <"$manifest"
    if [ "$missing" -ne 0 ]; then
      return 1
    fi
    cleanup_legacy_parts "$dir" "$base"
    echo "[shard-bootstrap] keep existing shards: $target"
    return 0
  fi

  size="$(file_size_bytes "$target")"
  if [ "$size" -le "$MAX_BYTES" ]; then
    find "$dir" -maxdepth 1 -type f -name "${base}.part*" -delete >/dev/null 2>&1 || true
    rm -f "$manifest"
    cleanup_legacy_parts "$dir" "$base"
    return 0
  fi

  tmp_dir="$(mktemp -d)"
  split -b "$MAX_BYTES" -a 3 "$target" "$tmp_dir/${base}.part"

  local split_parts=()
  while IFS= read -r p; do
    if [ -n "$p" ]; then
      split_parts+=("$p")
    fi
  done <<EOF_PARTS
$(find "$tmp_dir" -maxdepth 1 -type f -name "${base}.part*" | sort)
EOF_PARTS

  if [ "${#split_parts[@]}" -lt 2 ]; then
    echo "[shard-bootstrap] split produced <2 parts for $target; keeping original" >&2
    rm -rf "$tmp_dir"
    return 0
  fi

  chunk_count="${#split_parts[@]}"
  find "$dir" -maxdepth 1 -type f -name "${base}.part*" -delete >/dev/null 2>&1 || true
  rm -f "$manifest"
  cleanup_legacy_parts "$dir" "$base"

  idx=0
  : >"$manifest"
  while [ "$idx" -lt "$chunk_count" ]; do
    local out_part="$dir/${base}.part$(printf '%03d' "$idx")"
    mv "${split_parts[$idx]}" "$out_part"
    echo "$(basename "$out_part")" >>"$manifest"
    idx=$((idx + 1))
  done

  {
    echo "(* Sharded bootstrap source placeholder for ${base}. *)"
    echo "(* Rehydrate before dune build with: scripts/hxhx/hydrate-bootstrap-shards.sh ${dir} *)"
  } >"$target"

  rm -rf "$tmp_dir"

  echo "[shard-bootstrap] sharded: $target (${size}B -> ${chunk_count} parts, max=${MAX_BYTES}B)"
}

local_targets=()
for item in "$@"; do
  while IFS= read -r t; do
    if [ -n "$t" ]; then
      local_targets+=("$t")
    fi
  done <<EOF_TARGETS
$(collect_targets "$item")
EOF_TARGETS
done

if [ "${#local_targets[@]}" -eq 0 ]; then
  echo "[shard-bootstrap] no targets"
  exit 0
fi

for target in "${local_targets[@]}"; do
  shard_file "$target"
done
