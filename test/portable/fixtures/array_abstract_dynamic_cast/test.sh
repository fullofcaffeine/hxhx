#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
echo "ARRAY_ABSTRACT_DYNAMIC_CAST:PASS"
