#!/usr/bin/env bash
set -euo pipefail
# The portable runner already compared native stdout with expected.stdout.
# Compare the same program with upstream Haxe eval so the golden stays honest.
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
echo "SORT_CALLBACK_SHAPES:PASS"
