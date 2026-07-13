#!/usr/bin/env bash
set -euo pipefail

# Exercise the runci wrapper without an upstream checkout or a real compiler. The failure case
# protects the user-facing diagnostic, while the success case protects the strict gate contract.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$ROOT/.tmp/runci-macro-no-emit-runner-fixture.$$"
fake_bin="$fixture/bin"
upstream="$fixture/upstream"

cleanup() {
  rm -rf "$fixture" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf "$fixture"
mkdir -p "$fake_bin" "$upstream/tests" "$upstream/std" "$fixture/utest"
: >"$upstream/tests/RunCi.hxml"

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/dune"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/ocamlc"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [ "${1:-}" = "list" ]; then' \
  '  echo "utest: [git]"' \
  'elif [ "${1:-}" = "--always" ] && [ "${2:-}" = "path" ] && [ "${3:-}" = "utest" ]; then' \
  '  echo "$FAKE_UTEST_PATH"' \
  'else' \
  '  echo "unexpected fake haxelib arguments: $*" >&2' \
  '  exit 64' \
  'fi' >"$fake_bin/haxelib"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [ "${FAKE_HXHX_MODE:-fail}" = "pass" ]; then' \
  '  echo "stage3=no_emit_ok"' \
  '  exit 0' \
  'fi' \
  'echo "fixture-hxhx-error: macro host unavailable" >&2' \
  'exit 23' >"$fake_bin/hxhx"
chmod +x "$fake_bin/dune" "$fake_bin/ocamlc" "$fake_bin/haxelib" "$fake_bin/hxhx"

runner_env=(
  "PATH=$fake_bin:$PATH"
  "HAXELIB_BIN=$fake_bin/haxelib"
  "HAXE_UPSTREAM_DIR=$upstream"
  "HAXE_STD_PATH=$upstream/std"
  "HXHX_BIN=$fake_bin/hxhx"
  "FAKE_UTEST_PATH=$fixture/utest"
)

set +e
failure_output="$(env "${runner_env[@]}" bash "$ROOT/scripts/hxhx/run-upstream-runci-macro-stage3-no-emit.sh" 2>&1)"
failure_code="$?"
set -e

if [ "$failure_code" != "23" ]; then
  echo "expected fake hxhx exit code 23, got $failure_code" >&2
  printf '%s\n' "$failure_output" >&2
  exit 1
fi
grep -Fq "fixture-hxhx-error: macro host unavailable" <<<"$failure_output"
grep -Fq "FAILED: hxhx stage3 no-emit rung exited with code 23" <<<"$failure_output"

success_output="$(env "${runner_env[@]}" FAKE_HXHX_MODE=pass bash "$ROOT/scripts/hxhx/run-upstream-runci-macro-stage3-no-emit.sh" 2>&1)"
grep -Fq "stage3=no_emit_ok" <<<"$success_output"

echo "runci macro no-emit runner fixture OK"
