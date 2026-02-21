#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AS_OF="$(date -u +%F)"

CI_WORKFLOW="$ROOT/.github/workflows/ci.yml"
BOOTSTRAP_REGEN="$ROOT/scripts/hxhx/regenerate-hxhx-bootstrap.sh"
REPLACEMENT_READY="$ROOT/scripts/hxhx/run-replacement-ready.sh"

usage() {
  cat <<'USAGE'
Usage: bash scripts/hxhx/self-hosting-status.sh

Prints a beginner-friendly self-hosting status matrix using repository/CI signals.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 0 ]; then
  echo "Unknown argument: $1" >&2
  usage >&2
  exit 2
fi

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

require_file "$CI_WORKFLOW"
require_file "$BOOTSTRAP_REGEN"
require_file "$REPLACEMENT_READY"

has_text() {
  local path="$1"
  local text="$2"
  grep -Fq -- "$text" "$path"
}

status_build_blocked="Not yet"
status_stage3_blocked="Not yet"
status_macro_blocked="Not yet"
status_bootstrap_stage0_free="Not yet"
status_replacement_blocked="Partial"

evidence_build="Missing stage0-free smoke build check."
evidence_stage3="Missing stage0-free stage3 compile check."
evidence_macro="Missing stage0-free macro selftest check."
evidence_bootstrap="Bootstrap regen still uses stage0 emit."
evidence_replacement="No strict stage0-forbidden replacement-ready lane yet."

if has_text "$CI_WORKFLOW" "stage0-free-smoke:" \
  && has_text "$CI_WORKFLOW" "HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used bash scripts/hxhx/build-hxhx.sh"; then
  status_build_blocked="Pass"
  evidence_build=".github/workflows/ci.yml job stage0-free-smoke"
fi

if has_text "$CI_WORKFLOW" "--target ocaml-stage3 --hxhx-no-emit"; then
  status_stage3_blocked="Pass"
  evidence_stage3=".github/workflows/ci.yml job stage0-free-smoke"
fi

if has_text "$CI_WORKFLOW" "--hxhx-macro-selftest"; then
  status_macro_blocked="Pass"
  evidence_macro=".github/workflows/ci.yml job stage0-free-smoke"
fi

if has_text "$BOOTSTRAP_REGEN" "haxe_args=(build.hxml -D ocaml_emit_only)"; then
  status_bootstrap_stage0_free="Not yet"
  evidence_bootstrap="scripts/hxhx/regenerate-hxhx-bootstrap.sh still executes stage0 haxe emit."
else
  status_bootstrap_stage0_free="Pass"
  evidence_bootstrap="scripts/hxhx/regenerate-hxhx-bootstrap.sh no longer stage0-bound."
fi

if has_text "$REPLACEMENT_READY" "HXHX_FORBID_STAGE0=1"; then
  status_replacement_blocked="Pass"
  evidence_replacement="scripts/hxhx/run-replacement-ready.sh enforces HXHX_FORBID_STAGE0."
elif has_text "$CI_WORKFLOW" "stage0-free-smoke:"; then
  status_replacement_blocked="Partial"
  evidence_replacement="Stage0-free smoke exists, but replacement-ready runner is not strict stage0-forbidden."
else
  status_replacement_blocked="Not yet"
  evidence_replacement="No stage0-free smoke and no strict replacement-ready lane."
fi

echo "HXHX self-hosting status matrix (as of $AS_OF)"
echo
echo "| Check | Current status | Evidence |"
echo "|---|---|---|"
echo "| Build hxhx with stage0 delegation blocked (HXHX_FORBID_STAGE0=1) | $status_build_blocked | $evidence_build |"
echo "| Run a stage3 compile path with stage0 blocked | $status_stage3_blocked | $evidence_stage3 |"
echo "| Run macro host selftest with stage0 blocked | $status_macro_blocked | $evidence_macro |"
echo "| Regenerate packages/hxhx/bootstrap_out without stage0 haxe | $status_bootstrap_stage0_free | $evidence_bootstrap |"
echo "| Replacement-ready gates pass with delegation blocked | $status_replacement_blocked | $evidence_replacement |"
