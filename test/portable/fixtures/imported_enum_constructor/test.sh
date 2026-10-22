#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
echo "IMPORTED_ENUM_CONSTRUCTOR:PASS"
