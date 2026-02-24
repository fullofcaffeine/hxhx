#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STRICT="${HXHX_PLUGIN_MATRIX_STRICT:-1}"
ALLOW_SKIP="${HXHX_PLUGIN_MATRIX_ALLOW_SKIP:-0}"
CORO_DIR="${HXHX_PLUGIN_CORO_DIR:-}"

for value_name in STRICT ALLOW_SKIP; do
  eval "value=\${$value_name}"
  case "$value" in
    0|1) ;;
    *)
      echo "Invalid $value_name=$value (expected 0 or 1)." >&2
      exit 2
      ;;
  esac
done

summary=()
failures=0

run_check() {
  local name="$1"
  local marker="$2"
  local cmd="$3"
  local required="${4:-1}"
  local start end elapsed code

  start="$(date +%s)"
  echo ""
  echo "== Plugin matrix check: $name"
  echo "== command: $cmd"

  set +e
  bash -lc "$cmd"
  code="$?"
  set -e

  end="$(date +%s)"
  elapsed="$((end - start))"

  if [ "$code" -eq 0 ]; then
    summary+=("$name: PASS (${elapsed}s)")
    echo "${marker}:PASS"
    return 0
  fi

  if [ "$required" = "0" ] || [ "$ALLOW_SKIP" = "1" ]; then
    summary+=("$name: SKIP (${elapsed}s, exit=$code)")
    echo "${marker}:SKIP"
    return 0
  fi

  summary+=("$name: FAIL (${elapsed}s, exit=$code)")
  echo "${marker}:FAIL"
  failures=1
  return "$code"
}

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cat >"$tmpdir/UtestMain.hx" <<'HX'
import utest.Assert;
import utest.Runner;
import utest.Test;

class PluginUtestCase extends Test {
	public function testSmoke() {
		Assert.isTrue(true);
	}
}

class UtestMain {
	static function main() {
		final runner = new Runner();
		runner.addCase(new PluginUtestCase());
		runner.run();
	}
}
HX

cat >"$tmpdir/TinkMain.hx" <<'HX'
class TinkMain {
	static function main() {
		Sys.println("plugin_tink_macro=ok");
	}
}
HX

run_check \
  "reflaxe.ocaml macro build fixture" \
  "PLUGIN_REFLAXE_OCAML" \
  "cd '$ROOT/packages/reflaxe.ocaml/examples/build-macro' && haxe build.hxml"

run_check \
  "utest macro library compile/run" \
  "PLUGIN_UTEST" \
  "haxe -cp '$tmpdir' -main UtestMain --interp -lib utest"

run_check \
  "tink_macro library resolution smoke" \
  "PLUGIN_TINK_MACRO" \
  "haxe -cp '$tmpdir' -main TinkMain --interp -lib tink_macro"

if [ -n "$CORO_DIR" ]; then
  run_check \
    "coro repository presence" \
    "PLUGIN_CORO" \
    "test -d '$CORO_DIR' && test -f '$CORO_DIR/tests.hxml' && test -f '$CORO_DIR/extraParams.hxml'"
else
  run_check \
    "coro repository presence" \
    "PLUGIN_CORO" \
    "echo 'Set HXHX_PLUGIN_CORO_DIR to run Coro compatibility checks.' >&2; exit 2" \
    "0"
fi

echo ""
echo "== Plugin matrix summary"
for line in "${summary[@]}"; do
  echo "$line"
done

if [ "$failures" -ne 0 ]; then
  echo "PLUGIN_MATRIX:FAIL"
  exit 1
fi

if [ "$STRICT" = "1" ] && [ -z "$CORO_DIR" ] && [ "$ALLOW_SKIP" != "1" ]; then
  echo "PLUGIN_MATRIX:FAIL"
  echo "Strict plugin matrix requires HXHX_PLUGIN_CORO_DIR for Coro coverage." >&2
  exit 1
fi

echo "PLUGIN_MATRIX:PASS"
