#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d "$ROOT/.tmp/hxhx-bootstrap-ocaml-eval-hxml.XXXXXX")"
BUILD_DIR="$TEST_TMP/bootstrap_build"
BUILD_LOG="$TEST_TMP/build.log"
RUN_LOG="$TEST_TMP/run.log"
FAKE_HAXE="$TEST_TMP/haxe-log.sh"
INVOCATION_LOG="$TEST_TMP/invocation.log"
EXAMPLE_DIR="$ROOT/packages/reflaxe.ocaml/examples/build-macro"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

cat >"$FAKE_HAXE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'PWD=%s\n' "$PWD" > "${INVOCATION_LOG:?missing INVOCATION_LOG}"
printf 'ARGV_BEGIN\n' >> "${INVOCATION_LOG:?missing INVOCATION_LOG}"
for a in "$@"; do
  printf '%s\n' "$a" >> "${INVOCATION_LOG:?missing INVOCATION_LOG}"
done
printf 'ARGV_END\n' >> "${INVOCATION_LOG:?missing INVOCATION_LOG}"
exec haxe "$@"
EOF
chmod +x "$FAKE_HAXE"

(
  cd "$ROOT"
  HXHX_BOOTSTRAP_BUILD_DIR="$BUILD_DIR" \
  bash scripts/hxhx/build-hxhx.sh >"$BUILD_LOG" 2>&1
)

BIN_PATH="$(tail -n 1 "$BUILD_LOG")"
if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
  echo "Missing built hxhx executable path from build-hxhx.sh." >&2
  sed -n '1,160p' "$BUILD_LOG" >&2 || true
  exit 1
fi

(
  cd "$EXAMPLE_DIR"
  rm -rf out
  INVOCATION_LOG="$INVOCATION_LOG" \
  HXHX_REPO_ROOT="$ROOT" \
  HAXE_BIN="$FAKE_HAXE" \
  "$BIN_PATH" --ocaml-eval build.hxml -D ocaml_build=native >"$RUN_LOG" 2>&1
)

if grep -Fxq -- '--library' "$INVOCATION_LOG"; then
  echo "Unexpected --library injection in ocaml-eval forwarded args." >&2
  cat "$INVOCATION_LOG" >&2
  exit 1
fi

if grep -Fxq -- '--no-output' "$INVOCATION_LOG"; then
  echo "Unexpected --no-output injection in ocaml-eval forwarded args." >&2
  cat "$INVOCATION_LOG" >&2
  exit 1
fi

if grep -Fxq 'ocaml_output=out' "$INVOCATION_LOG"; then
  echo "Unexpected default ocaml_output injection in ocaml-eval forwarded args." >&2
  cat "$INVOCATION_LOG" >&2
  exit 1
fi

if [ ! -f "$EXAMPLE_DIR/out/_build/default/out.exe" ]; then
  echo "Missing built example artifact after ocaml-eval run." >&2
  sed -n '1,160p' "$RUN_LOG" >&2 || true
  exit 1
fi

echo "BUILD_HXHX_BOOTSTRAP_OCAML_EVAL_HXML_SMOKE:PASS"
