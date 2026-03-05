#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d)"
TRACE_FILE="$TEST_TMP/fake-haxe.trace"
FAKE_HAXE="$TEST_TMP/fake-haxe.sh"
OUTPUT_FILE="$TEST_TMP/build.output"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

cat >"$FAKE_HAXE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

trace_file="${FAKE_HAXE_TRACE:?missing FAKE_HAXE_TRACE}"
printf '%s\n' "$*" >>"$trace_file"

has_connect=0
for arg in "$@"; do
  if [ "$arg" = "--connect" ]; then
    has_connect=1
    break
  fi
done

if [ "$has_connect" = "1" ]; then
  sleep 10
  exit 0
fi

mkdir -p out/_build/default
: > out/_build/default/out.bc
exit 0
EOF
chmod +x "$FAKE_HAXE"

(
  cd "$ROOT"
  HXHX_FORCE_STAGE0=1 \
  HAXE_BIN="$FAKE_HAXE" \
  HAXE_CONNECT=127.0.0.1:9999 \
  HXHX_STAGE0_HEARTBEAT=1 \
  HXHX_STAGE0_FAILFAST_SECS=0 \
  HXHX_STAGE0_CONNECT_IDLE_SECS=2 \
  FAKE_HAXE_TRACE="$TRACE_FILE" \
  bash scripts/hxhx/build-hxhx.sh >"$OUTPUT_FILE" 2>&1
)

if ! grep -q "rerunning once without --connect after idle-handoff detection" "$OUTPUT_FILE"; then
  echo "Expected connect-retry message in build output." >&2
  sed -n '1,120p' "$OUTPUT_FILE" >&2
  exit 1
fi

if ! grep -q -- '--connect' "$TRACE_FILE"; then
  echo "Expected first fake stage0 invocation to include --connect." >&2
  cat "$TRACE_FILE" >&2 || true
  exit 1
fi

if ! grep -q -E '^build\.hxml -D ocaml_build=byte$' "$TRACE_FILE"; then
  echo "Expected retry invocation without --connect." >&2
  cat "$TRACE_FILE" >&2 || true
  exit 1
fi

last_line="$(tail -n 1 "$OUTPUT_FILE")"
expected_path="$ROOT/packages/hxhx/out/_build/default/out.bc"
if [ "$last_line" != "$expected_path" ]; then
  echo "Unexpected build output path: $last_line" >&2
  sed -n '1,120p' "$OUTPUT_FILE" >&2
  exit 1
fi

echo "BUILD_HXHX_CONNECT_RETRY_SMOKE:PASS"
