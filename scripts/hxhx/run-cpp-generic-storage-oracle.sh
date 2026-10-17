#!/usr/bin/env bash
# Compare authored generic storage observations with the pinned upstream targets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="$(command -v "${HAXE_BIN:-haxe}")"
HAXELIB_BIN="$(command -v "${HAXELIB_BIN:-haxelib}")"
export PATH="$(dirname "$HAXELIB_BIN"):$PATH"
WORK="${HXHX_CPP_GENERIC_ORACLE_WORKDIR:-$ROOT/.tmp/cpp-generic-storage-oracle}"
FIXTURE="$ROOT/test/fixtures/cpp_generic_storage_oracle"
mkdir -p "$WORK"
cd "$WORK"
WORK="$PWD"

if [[ "$("$HAXE_BIN" --version)" != "4.3.7" ]]; then
  echo 'Generic storage reference requires upstream Haxe 4.3.7.' >&2
  exit 2
fi
if ! "$HAXELIB_BIN" path hxcpp | rg -Fxq -- '-D hxcpp=4.3.2'; then
  echo 'Select an isolated haxelib repository containing hxcpp 4.3.2; see the fixture README.' >&2
  exit 2
fi
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT=gtimeout
else
  TIMEOUT=timeout
fi
export HXCPP_COMPILE_THREADS=2
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$FIXTURE" -main Main -cpp "$WORK/native" > build.log 2>&1; then
  tail -40 build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.cpp.stdout 2> actual.cpp.stderr
test ! -s actual.cpp.stderr
diff -u "$FIXTURE/expected.cpp.stdout" actual.cpp.stdout
"$TIMEOUT" 30 "$HAXE_BIN" -cp "$FIXTURE" -main Main --interp > actual.interp.stdout 2> actual.interp.stderr
test ! -s actual.interp.stderr
diff -u "$FIXTURE/expected.interp.stdout" actual.interp.stdout
# Reuse the native build directory only after retaining the first program's
# outputs. The second authored program exercises actual generic field effects.
FIELD_FIXTURE="$ROOT/test/fixtures/cpp_generic_field_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$FIELD_FIXTURE" -main Main -cpp "$WORK/native" > field-build.log 2>&1; then
  tail -40 field-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.field.stdout 2> actual.field.stderr
test ! -s actual.field.stderr
diff -u "$FIELD_FIXTURE/expected.stdout" actual.field.stdout
METHOD_FIXTURE="$ROOT/test/fixtures/cpp_generic_method_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$METHOD_FIXTURE" -main Main -cpp "$WORK/native" > method-build.log 2>&1; then
  tail -40 method-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.method.stdout 2> actual.method.stderr
test ! -s actual.method.stderr
diff -u "$METHOD_FIXTURE/expected.stdout" actual.method.stdout
CONTEXT_FIXTURE="$ROOT/test/fixtures/cpp_generic_method_context_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$CONTEXT_FIXTURE" -main Main -cpp "$WORK/native" > context-build.log 2>&1; then
  tail -40 context-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.context.stdout 2> actual.context.stderr
test ! -s actual.context.stderr
diff -u "$CONTEXT_FIXTURE/expected.stdout" actual.context.stdout
INITIALIZER_FIXTURE="$ROOT/test/fixtures/cpp_generic_initializer_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$INITIALIZER_FIXTURE" -main Main -cpp "$WORK/native" > initializer-build.log 2>&1; then
  tail -40 initializer-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.initializer.stdout 2> actual.initializer.stderr
test ! -s actual.initializer.stderr
diff -u "$INITIALIZER_FIXTURE/expected.stdout" actual.initializer.stdout
INITIALIZER_METHOD_FIXTURE="$ROOT/test/fixtures/cpp_generic_initializer_method_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$INITIALIZER_METHOD_FIXTURE" -main Main -cpp "$WORK/native" > initializer-method-build.log 2>&1; then
  tail -40 initializer-method-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.initializer-method.stdout 2> actual.initializer-method.stderr
test ! -s actual.initializer-method.stderr
diff -u "$INITIALIZER_METHOD_FIXTURE/expected.stdout" actual.initializer-method.stdout
CONSTRUCTOR_CONTEXT_FIXTURE="$ROOT/test/fixtures/cpp_generic_constructor_context_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$CONSTRUCTOR_CONTEXT_FIXTURE" -main Main -cpp "$WORK/native" > constructor-context-build.log 2>&1; then
  tail -40 constructor-context-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.constructor-context.stdout 2> actual.constructor-context.stderr
test ! -s actual.constructor-context.stderr
diff -u "$CONSTRUCTOR_CONTEXT_FIXTURE/expected.stdout" actual.constructor-context.stdout
RUNTIME_CONTEXT_FIXTURE="$ROOT/test/fixtures/cpp_generic_runtime_context_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$RUNTIME_CONTEXT_FIXTURE" -main Main -cpp "$WORK/native" > runtime-context-build.log 2>&1; then
  tail -40 runtime-context-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.runtime-context.stdout 2> actual.runtime-context.stderr
test ! -s actual.runtime-context.stderr
diff -u "$RUNTIME_CONTEXT_FIXTURE/expected.stdout" actual.runtime-context.stdout
CALLABLE_FIXTURE="$ROOT/test/fixtures/cpp_generic_callable_transfer_seed"
if ! "$TIMEOUT" 300 "$HAXE_BIN" -cp "$CALLABLE_FIXTURE" -main Main -cpp "$WORK/native" > callable-build.log 2>&1; then
  tail -40 callable-build.log >&2
  exit 1
fi
"$TIMEOUT" 30 "$WORK/native/Main" > actual.callable.stdout 2> actual.callable.stderr
test ! -s actual.callable.stderr
diff -u "$CALLABLE_FIXTURE/expected.stdout" actual.callable.stdout
echo 'CPP_GENERIC_STORAGE_ORACLE:PASS'
