#!/usr/bin/env bash
# Strict errors abort macro execution, so observe their order in a fresh compiler process.
set -euo pipefail
cd "$(dirname "$0")/.."
order_tmp=$(mktemp -d)
trap 'rm -rf "$order_tmp"' EXIT
order_args=(-cp packages/reflaxe.ocaml/src -cp test/reflaxe_ocaml_native_surface/src
  --macro 'NativeSurfaceOrderFixture.run()' --no-output)

haxe "${order_args[@]}"
order_status=0
haxe "${order_args[@]}" -D native_surface_order_strict >"$order_tmp/stdout" 2>"$order_tmp/stderr" || order_status=$?
if [[ "$order_status" != 1 ]]; then
  cat "$order_tmp/stdout" "$order_tmp/stderr" >&2
  echo "Expected the first strict diagnostic to fail compilation with status 1." >&2
  exit 1
fi
if ! grep -Fq 'ocaml metal strict mode forbids reflection call `Reflect.fields`' "$order_tmp/stderr"; then
  cat "$order_tmp/stderr" >&2
  echo "The expected first strict diagnostic was replaced." >&2
  exit 1
fi
if grep -Fq NATIVE_SURFACE_INVENTORY_READ "$order_tmp/stdout"; then
  echo "The declaration inventory was read before the first strict error." >&2
  exit 1
fi
echo "NATIVE_SURFACE_FIRST_ERROR:PASS"

# Each side receives fresh compiler types; reading one graph cannot prepare the other.
owned_args=(-cp packages/reflaxe.ocaml/src -cp test/reflaxe_ocaml_native_surface/src
  -D reflaxe_lifecycle_test --macro 'NativeSurfaceOwnedFixture.run()' --no-output)
haxe "${owned_args[@]}" -D native_surface_reference >"$order_tmp/reference"
haxe "${owned_args[@]}" >"$order_tmp/candidate"
diff -u "$order_tmp/reference" "$order_tmp/candidate"
echo "NATIVE_SURFACE_OWNED_TYPES:PASS"

body_args=(-cp packages/reflaxe.ocaml/src -cp test/reflaxe_ocaml_native_surface/src
  -D reflaxe_lifecycle_test --macro 'NativeSurfaceBodyFixture.run()' --no-output)
haxe "${body_args[@]}" -D native_surface_reference >"$order_tmp/body-reference"
haxe "${body_args[@]}" >"$order_tmp/body-candidate"
diff -u "$order_tmp/body-reference" "$order_tmp/body-candidate"
echo "NATIVE_SURFACE_BODY:PASS"
