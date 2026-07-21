#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_ROOT="$ROOT/test/reflaxe_ocaml_static_initialization/src"
mkdir -p "$ROOT/.tmp"
WORK_ROOT="$(mktemp -d "$ROOT/.tmp/reflaxe-ocaml-static-init.XXXXXX")"
WORK_RELATIVE="${WORK_ROOT#"$ROOT"/}"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command for static-initialization parity: $1" >&2
    exit 2
  fi
}

assert_exact() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" != "$expected" ]; then
    echo "$label produced unexpected output" >&2
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    exit 1
  fi
}

require_command haxe
require_command node
require_command neko
require_command dune
require_command ocamlc
cd "$ROOT"

cross_expected=$'cross=1/2/2\nevents=B.value=2,A.first=1,A.fromB=2'
cross_interp="$(haxe -cp "$SOURCE_ROOT" -main CrossMain --interp)"
haxe -cp "$SOURCE_ROOT" -main CrossMain -js "$WORK_ROOT/cross.js"
cross_js="$(node "$WORK_ROOT/cross.js")"
haxe -cp "$SOURCE_ROOT" -main CrossMain -neko "$WORK_ROOT/cross.n"
cross_neko="$(neko "$WORK_ROOT/cross.n")"
assert_exact "Haxe interpreter cross-module initialization" "$cross_expected" "$cross_interp"
assert_exact "Haxe JavaScript cross-module initialization" "$cross_expected" "$cross_js"
assert_exact "Haxe Neko cross-module initialization" "$cross_expected" "$cross_neko"

mkdir -p "$WORK_ROOT/ocaml-cross"
haxe -cp "$SOURCE_ROOT" -main CrossMain --no-output -lib reflaxe.ocaml -D "ocaml_output=$WORK_RELATIVE/ocaml-cross/out" -D ocaml_build=native
cross_ocaml="$($WORK_ROOT/ocaml-cross/out/_build/default/out.exe)"
assert_exact "reflaxe.ocaml cross-module initialization" "$cross_expected" "$cross_ocaml"

set +e
haxe -cp "$SOURCE_ROOT" -main FailureMain --interp >"$WORK_ROOT/failure-interp.log" 2>&1
failure_interp_status=$?
set -e
if [ "$failure_interp_status" -eq 0 ] || ! grep -Fq "initializer failed" "$WORK_ROOT/failure-interp.log"; then
  echo "Haxe interpreter should abort before main when a static initializer throws" >&2
  cat "$WORK_ROOT/failure-interp.log" >&2
  exit 1
fi

mkdir -p "$WORK_ROOT/ocaml-failure"
haxe -cp "$SOURCE_ROOT" -main FailureMain --no-output -lib reflaxe.ocaml -D "ocaml_output=$WORK_RELATIVE/ocaml-failure/out" -D ocaml_build=native
set +e
"$WORK_ROOT/ocaml-failure/out/_build/default/out.exe" >"$WORK_ROOT/failure-ocaml.log" 2>&1
failure_ocaml_status=$?
set -e
if [ "$failure_ocaml_status" -eq 0 ] || ! grep -Fq "initializer failed" "$WORK_ROOT/failure-ocaml.log" || grep -Fq "main-started" "$WORK_ROOT/failure-ocaml.log"; then
  echo "reflaxe.ocaml should preserve a static initializer failure before main" >&2
  cat "$WORK_ROOT/failure-ocaml.log" >&2
  exit 1
fi

set +e
haxe -cp "$SOURCE_ROOT" -main CycleMain --interp >"$WORK_ROOT/cycle-interp.log" 2>&1
cycle_interp_status=$?
set -e
if [ "$cycle_interp_status" -eq 0 ] || ! grep -Fq "WStaticInitOrder" "$WORK_ROOT/cycle-interp.log" || ! grep -Fq "Invalid operation" "$WORK_ROOT/cycle-interp.log"; then
  echo "Haxe interpreter cycle control no longer matches the recorded 4.3.7 behavior" >&2
  cat "$WORK_ROOT/cycle-interp.log" >&2
  exit 1
fi

haxe -cp "$SOURCE_ROOT" -main CycleMain -js "$WORK_ROOT/cycle.js" >"$WORK_ROOT/cycle-js-compile.log" 2>&1
cycle_js="$(node "$WORK_ROOT/cycle.js")"
assert_exact "Haxe JavaScript cycle control" $'cycle=NaN/NaN\nevents=CycleB.value=NaN,CycleA.value=NaN' "$cycle_js"

haxe -cp "$SOURCE_ROOT" -main CycleMain -neko "$WORK_ROOT/cycle.n" >"$WORK_ROOT/cycle-neko-compile.log" 2>&1
set +e
neko "$WORK_ROOT/cycle.n" >"$WORK_ROOT/cycle-neko.log" 2>&1
cycle_neko_status=$?
set -e
if [ "$cycle_neko_status" -eq 0 ] || ! grep -Fq "Invalid operation" "$WORK_ROOT/cycle-neko.log"; then
  echo "Haxe Neko cycle control no longer matches the recorded 4.3.7 behavior" >&2
  cat "$WORK_ROOT/cycle-neko.log" >&2
  exit 1
fi

mkdir -p "$WORK_ROOT/ocaml-cycle"
set +e
haxe -cp "$SOURCE_ROOT" -main CycleMain --no-output -lib reflaxe.ocaml -D "ocaml_output=$WORK_RELATIVE/ocaml-cycle/out" -D ocaml_build=native >"$WORK_ROOT/cycle-ocaml.log" 2>&1
cycle_ocaml_status=$?
set -e
if [ "$cycle_ocaml_status" -eq 0 ] || ! grep -Fq "ocaml-static-storage:initializer-cycle" "$WORK_ROOT/cycle-ocaml.log"; then
  echo "reflaxe.ocaml should reject a mutable-static initializer cycle before native compilation" >&2
  cat "$WORK_ROOT/cycle-ocaml.log" >&2
  exit 1
fi
if grep -Fq "dune build failed" "$WORK_ROOT/cycle-ocaml.log"; then
  echo "Static-initializer cycle reached Dune instead of failing in the target planner" >&2
  cat "$WORK_ROOT/cycle-ocaml.log" >&2
  exit 1
fi

echo "REFLAXE_OCAML_STATIC_INITIALIZATION_PARITY:PASS"
