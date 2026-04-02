#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:?usage: sanitize-stage3-emit-dir.sh <out-dir>}"

# Keep this intentionally conservative. The stage0 source lane calls this hook
# before dune so the path is stable across real builds and smoke tests. The hook
# is cleanup/verification only: source generation owns semantic lowering, and the
# normal bootstrap path owns snapshot finalization.
if [ ! -d "$out_dir" ]; then
  echo "Missing stage3 emit dir: $out_dir" >&2
  exit 1
fi

find "$out_dir" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
