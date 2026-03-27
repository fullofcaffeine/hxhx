#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:?usage: sanitize-stage3-emit-dir.sh <out-dir>}"
root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
helper="$root_dir/scripts/hxhx/bootstrap_patch_helper.py"

# Keep this intentionally conservative. The stage0 source lane now calls this hook
# before dune so the path is stable across real builds and smoke tests. For now the
# only universally safe sanitation is ensuring the directory exists, repairing the
# known generated EmitterStage typed-map seam, and dropping transient shell bytecode
# noise if it was copied into the emit dir by a test stub.
if [ ! -d "$out_dir" ]; then
  echo "Missing stage3 emit dir: $out_dir" >&2
  exit 1
fi

if [ -f "$out_dir/EmitterStage.ml" ]; then
  python3 "$helper" patch-extend-ty-ident-call-reprs "$out_dir/EmitterStage.ml"
  python3 "$helper" patch-stmt-list-local-hint-reprs "$out_dir/EmitterStage.ml"
fi

find "$out_dir" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
