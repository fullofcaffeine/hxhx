#!/usr/bin/env bash
set -euo pipefail

# Validate a local compiler artifact by the complete inputs consumed by the
# stage0 current-source build. This is deliberately weaker than exact-commit
# provenance and must never be used by release or parity proof runners.

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${HXHX_CURRENT_SOURCE_ROOT:-$SCRIPT_ROOT}"
requested_bin="${1:-${HXHX_BIN:-}}"
meta_path="${HXHX_CURRENT_SOURCE_META:-$ROOT/packages/hxhx/out/hxhx-current-source.env}"
fingerprint_tool="$SCRIPT_ROOT/scripts/hxhx/current-source-input-fingerprint.js"
expected_profile="${HXHX_CURRENT_SOURCE_EXPECTED_PROFILE:-full}"

fail() {
  echo "validate-developer-current-source-hxhx-bin: $*" >&2
  exit 1
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi
  fail "missing SHA-256 tool (need sha256sum or shasum)"
}

[ -n "$requested_bin" ] || fail "missing HXHX_BIN/path argument"
case "$requested_bin" in
  /*) : ;;
  */*) requested_bin="$ROOT/$requested_bin" ;;
  *) fail "HXHX_BIN must be an explicit path for current-source provenance: $requested_bin" ;;
esac

[ -f "$requested_bin" ] || fail "HXHX_BIN does not exist: $requested_bin"
if [ ! -x "$requested_bin" ] && [[ "$requested_bin" != *.bc ]]; then
  fail "HXHX_BIN is neither executable nor OCaml bytecode (*.bc): $requested_bin"
fi
[ -f "$meta_path" ] || fail "missing provenance metadata: $meta_path"
[ -f "$fingerprint_tool" ] || fail "missing compiler-input fingerprint tool: $fingerprint_tool"
command -v node >/dev/null 2>&1 || fail "missing node on PATH"

# shellcheck disable=SC1090
. "$meta_path"

[ "${HXHX_BIN_PROVENANCE:-}" = "current-source-stage0" ] || fail "unexpected HXHX_BIN_PROVENANCE=${HXHX_BIN_PROVENANCE:-missing}"
[ "${HXHX_BIN_BUILD_PROFILE:-}" = "$expected_profile" ] || fail "expected HXHX_BIN_BUILD_PROFILE=$expected_profile, got ${HXHX_BIN_BUILD_PROFILE:-missing}"
[ "${HXHX_BIN:-}" = "$requested_bin" ] || fail "metadata HXHX_BIN ($HXHX_BIN) does not match requested path ($requested_bin)"
[ "${HXHX_BIN_INPUT_FINGERPRINT_SCHEMA:-}" = "hxhx.current-source-inputs.v1" ] || fail "missing current developer-cache fingerprint metadata; run scripts/hxhx/build-current-source-hxhx.sh once"
[ -n "${HXHX_BIN_INPUT_SHA256:-}" ] || fail "missing compiler input SHA-256"
[ -n "${HXHX_BIN_ARTIFACT_SHA256:-}" ] || fail "missing compiler artifact SHA-256"

artifact_sha256="$(sha256_file "$requested_bin")"
[ "$artifact_sha256" = "$HXHX_BIN_ARTIFACT_SHA256" ] || fail "compiler artifact changed since the recorded build"

current_input_sha256="$(node "$fingerprint_tool" --root "$ROOT")"
[ "$current_input_sha256" = "$HXHX_BIN_INPUT_SHA256" ] || fail "compiler input fingerprint changed; a fresh current-source build is required"

current_head="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "HXHX_DEVELOPER_CURRENT_SOURCE_CACHE:REUSE profile=$expected_profile input_sha256=$current_input_sha256 built_head=${HXHX_BIN_SOURCE_HEAD:-unknown} current_head=$current_head" >&2
echo "$requested_bin"
