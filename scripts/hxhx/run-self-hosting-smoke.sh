#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

need_cmd() {
  local cmd="$1"
  local label="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Skipping self-hosting smoke: missing $label ('$cmd')."
    exit 0
  fi
}

need_cmd dune "dune"
need_cmd ocamlc "ocaml compiler"

echo "== Self-hosting smoke: build hxhx with stage0 delegation blocked"
build_log="$(mktemp)"
set +e
HXHX_BIN_RAW="$(
  HXHX_FORBID_STAGE0=1 \
  HAXE_BIN=/definitely-not-used \
  bash "$ROOT/scripts/hxhx/build-hxhx.sh" 2>&1 | tee "$build_log"
)"
build_code="${PIPESTATUS[0]}"
set -e
if [ "$build_code" -ne 0 ]; then
  if grep -Fq "currentMutableLocalRefs = ref (HxMap.create_string () : Obj.t)" "$build_log"; then
    echo "Self-hosting smoke failed: bootstrap snapshot is stale/broken (EmitterStage mutable-ref tracker mismatch)." >&2
    echo "Repair suggestion: refresh snapshots with stage0 regen and retry." >&2
    echo "  bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --incremental --verify" >&2
  fi
  rm -f "$build_log"
  exit "$build_code"
fi
rm -f "$build_log"
HXHX_BIN="$(printf "%s\n" "$HXHX_BIN_RAW" | tail -n 1)"
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Missing hxhx binary from build-hxhx.sh." >&2
  exit 1
fi
echo "hxhx_bin=$HXHX_BIN"

echo "== Self-hosting smoke: stage3 no-emit compile path"
tmp_stage3="$(mktemp -d)"
trap 'rm -rf "$tmp_stage3"' EXIT
stage3_out="$(
  HXHX_FORBID_STAGE0=1 \
  HAXE_BIN=/definitely-not-used \
  "$HXHX_BIN" \
    --target ocaml-stage3 \
    --hxhx-no-emit \
    -cp "$ROOT/workloads/hih-compiler/fixtures/src" \
    -main demo.A \
    --hxhx-out "$tmp_stage3"
)"
echo "$stage3_out"
echo "$stage3_out" | grep -q '^stage3=no_emit_ok$'

echo "== Self-hosting smoke: build macro host with stage0 delegation blocked"
HXHX_MACRO_HOST_EXE="$(
  HXHX_FORBID_STAGE0=1 \
  HAXE_BIN=/definitely-not-used \
  bash "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1
)"
if [ -z "$HXHX_MACRO_HOST_EXE" ] || [ ! -f "$HXHX_MACRO_HOST_EXE" ]; then
  echo "Missing macro host binary from build-hxhx-macro-host.sh." >&2
  exit 1
fi
echo "macro_host_exe=$HXHX_MACRO_HOST_EXE"

echo "== Self-hosting smoke: macro host selftest"
macro_out="$(
  HXHX_FORBID_STAGE0=1 \
  HAXE_BIN=/definitely-not-used \
  HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" \
  "$HXHX_BIN" --hxhx-macro-selftest
)"
echo "$macro_out"
echo "$macro_out" | grep -q '^macro_host=ok$'
echo "$macro_out" | grep -q '^OK hxhx macro rpc$'

echo "== Self-hosting smoke: ok"
