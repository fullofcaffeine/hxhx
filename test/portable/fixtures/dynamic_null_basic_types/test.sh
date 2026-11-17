#!/usr/bin/env bash
set -euo pipefail
# expected.stdout follows the static-target rule decided on 2026-11-17 (haxe_ocaml-9cqxj):
# a null moved into Int, Float, or Bool gives 0, 0.0, or false, as on JVM, Java, C#, and C++.
# `haxe --interp` is a dynamic target and prints null for the first line, so only the second
# line, which holds no null, is compared with it.
diff -u <(sed -n 2p expected.stdout) <("${HAXE_BIN:-haxe}" -cp src -main Main --interp | sed -n 2p)
echo "DYNAMIC_NULL_BASIC_TYPES:PASS"
