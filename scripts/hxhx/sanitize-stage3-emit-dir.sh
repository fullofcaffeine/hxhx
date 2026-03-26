#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:?usage: sanitize-stage3-emit-dir.sh <out-dir>}"

# Keep this intentionally conservative. The stage0 source lane now calls this hook
# before dune so the path is stable across real builds and smoke tests. For now the
# only universally safe sanitation is ensuring the directory exists and dropping
# transient shell bytecode noise if it was copied into the emit dir by a test stub.
if [ ! -d "$out_dir" ]; then
  echo "Missing stage3 emit dir: $out_dir" >&2
  exit 1
fi

find "$out_dir" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
