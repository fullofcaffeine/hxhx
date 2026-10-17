#!/usr/bin/env bash
# Run authored startup observations through upstream Haxe and its native C++ runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="$(command -v "${HAXE_BIN:-haxe}")"
HAXELIB_BIN="$(command -v "${HAXELIB_BIN:-haxelib}")"
# The compiler launches haxelib itself; preserve the caller-selected executable
# when npm places project shims before the host toolchain on PATH.
export PATH="$(dirname "$HAXELIB_BIN"):$PATH"
FIXTURES="$ROOT/test/fixtures/cpp_static_startup_oracle"
WORK="${HXHX_CPP_STARTUP_ORACLE_WORKDIR:-$ROOT/.tmp/cpp-static-startup-oracle}"
mkdir -p "$WORK"
cd "$WORK"
WORK="$PWD"
BUILD="$WORK/native"
RECEIPTS="$WORK/receipts"
mkdir -p "$RECEIPTS"

if [[ "$("$HAXE_BIN" --version)" != "4.3.7" ]]; then
  echo 'C++ startup oracle requires upstream Haxe 4.3.7.' >&2
  exit 2
fi
if ! "$HAXELIB_BIN" path hxcpp | rg -Fxq -- '-D hxcpp=4.3.2'; then
  echo "Select HAXELIB_BIN with hxcpp 4.3.2 available under $WORK; see the fixture README." >&2
  exit 2
fi
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT=gtimeout
else
  TIMEOUT=timeout
fi
export HXCPP_COMPILE_THREADS=2

# Cases intentionally share one native build directory to reuse hxcpp runtime objects.
# Each Haxe invocation rewrites the selected program before compilation and observation.
run_case() {
  local fixture="$1" mode="$2" expected="$3"
  local receipt="$RECEIPTS/$fixture-$mode"
  local dce=std
  if [[ "$fixture" == extern ]]; then
    dce=no
  fi
  if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$FIXTURES/$fixture" -main Main -D "$mode" -dce "$dce" -cpp "$BUILD" >"$receipt.build.log" 2>&1; then
    tail -40 "$receipt.build.log" >&2
    return 1
  fi
  "$TIMEOUT" 30 "$BUILD/Main" >"$receipt.stdout" 2>"$receipt.stderr"
  if [[ -s "$receipt.stderr" ]]; then
    cat "$receipt.stderr" >&2
    return 1
  fi
  diff -u "$FIXTURES/$fixture/$expected" "$receipt.stdout"
  echo "CPP_STATIC_STARTUP_ORACLE_CASE:PASS case=$fixture/$mode"
}

run_case order none expected.cpp.stdout
"$TIMEOUT" 30 "$HAXE_BIN" -cp "$FIXTURES/order" -main Main --interp >"$RECEIPTS/order-interp.stdout"
diff -u "$FIXTURES/order/expected.interp.stdout" "$RECEIPTS/order-interp.stdout"
for mode in none eager invoked stored dead; do
  run_case transitive "$mode" "expected.$mode.stdout"
done
for mode in none dead_call type_only deferred_call; do
  run_case modules "$mode" "expected.$mode.stdout"
done
run_case cycle none expected.cpp.stdout
run_case extern none expected.cpp.stdout
echo 'CPP_STATIC_STARTUP_ORACLE:PASS native_cases=12 interp_contrast=1'
