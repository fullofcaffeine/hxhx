#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-runtime}"
HAXE_SENTINEL="${HXHX_STAGE0_POLICY_SENTINEL_HAXE_BIN:-/definitely-not-used}"

case "$MODE" in
  runtime|release) ;;
  *)
    echo "Usage: bash scripts/hxhx/check-stage0-policy.sh [runtime|release]" >&2
    exit 2
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "== Stage0 policy check ($MODE)"
echo "== Building hxhx with stage0 delegation forbidden"
HXHX_BIN="$(HXHX_FORBID_STAGE0=1 HAXE_BIN="$HAXE_SENTINEL" bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Stage0 policy check failed: missing hxhx binary from build-hxhx.sh." >&2
  exit 1
fi

echo "== Checking runtime path blocks delegation and keeps builtin stage3 path"
stage3_out="$(
  HXHX_FORBID_STAGE0=1 HAXE_BIN="$HAXE_SENTINEL" \
  "$HXHX_BIN" --target ocaml-stage3 --hxhx-no-emit \
    -cp "$ROOT/workloads/hih-compiler/fixtures/src" \
    -main demo.A \
    --hxhx-out "$tmpdir/stage3_out"
)"
echo "$stage3_out" | grep -q '^stage3=no_emit_ok$'

version_log="$tmpdir/version_guard.log"
if ! HXHX_FORBID_STAGE0=1 HAXE_BIN="$HAXE_SENTINEL" "$HXHX_BIN" --version >"$version_log" 2>&1; then
  echo "Stage0 policy check failed: --version must be served locally under HXHX_FORBID_STAGE0=1." >&2
  sed -n '1,40p' "$version_log" >&2 || true
  exit 1
fi
if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+' "$version_log"; then
  echo "Stage0 policy check failed: unexpected --version output." >&2
  sed -n '1,40p' "$version_log" >&2 || true
  exit 1
fi

if [ "$MODE" = "release" ]; then
  echo "== Checking release path macro-host build with stage0 delegation forbidden"
  HXHX_MACRO_HOST_EXE="$(HXHX_FORBID_STAGE0=1 HAXE_BIN="$HAXE_SENTINEL" bash "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
  if [ -z "$HXHX_MACRO_HOST_EXE" ] || [ ! -f "$HXHX_MACRO_HOST_EXE" ]; then
    echo "Stage0 policy check failed: missing macro host binary from build-hxhx-macro-host.sh." >&2
    exit 1
  fi

  macro_out="$(
    HXHX_FORBID_STAGE0=1 HAXE_BIN="$HAXE_SENTINEL" HXHX_MACRO_HOST_EXE="$HXHX_MACRO_HOST_EXE" \
    "$HXHX_BIN" --hxhx-macro-selftest
  )"
  echo "$macro_out" | grep -q '^macro_host=ok$'
  echo "$macro_out" | grep -q '^OK hxhx macro rpc$'

  echo "== Checking dist packaging default policy is stage0-forbidden"
  dist_log="$tmpdir/dist.log"
  HXHX_VERSION="stage0-policy-smoke" SOURCE_DATE_EPOCH=0 HXHX_DIST_FORBID_STAGE0=1 HAXE_BIN="$HAXE_SENTINEL" \
    bash "$ROOT/scripts/hxhx/build-dist.sh" >"$dist_log" 2>&1
  artifact_path="$(awk '/^OK: /{print substr($0, 5)}' "$dist_log" | tail -n 1)"
  if [ -z "$artifact_path" ] || [ ! -f "$artifact_path" ]; then
    echo "Stage0 policy check failed: dist artifact missing." >&2
    sed -n '1,120p' "$dist_log" >&2 || true
    exit 1
  fi
  build_info_path="$ROOT/dist/hxhx/stage0-policy-smoke/$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)/BUILD_INFO.txt"
  if [ ! -f "$build_info_path" ]; then
    echo "Stage0 policy check failed: expected BUILD_INFO not found at $build_info_path." >&2
    exit 1
  fi
  grep -q "Stage0 Haxe: forbidden (HXHX_DIST_FORBID_STAGE0=1)" "$build_info_path"

  rm -rf "$ROOT/dist/hxhx/stage0-policy-smoke" \
    "$ROOT/dist/hxhx/hxhx-stage0-policy-smoke-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m).tar.gz" \
    "$ROOT/dist/hxhx/hxhx-stage0-policy-smoke-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m).tar.gz.sha256"
fi

echo "OK: stage0 policy ($MODE)"
