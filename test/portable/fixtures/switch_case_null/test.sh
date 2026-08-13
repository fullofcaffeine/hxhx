#!/usr/bin/env bash
set -euo pipefail

# Upstream Haxe 4.3.7 is the behavior oracle for the wildcard switch. It can
# place the same typed `source.copy()` occurrence in two branches. The native
# target must preserve the result without sharing one runtime-use identity
# across both generated OCaml output sites.
upstream_output="$(mktemp)"
native_output="$(mktemp)"
trap 'rm -f "$upstream_output" "$native_output"' EXIT

haxe -cp src --main Main --interp >"$upstream_output"
out/_build/default/out.exe >"$native_output"
diff -u "$upstream_output" "$native_output"
