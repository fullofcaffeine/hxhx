#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
node verify-report.js
echo "NULLABLE_ENUM_ARRAY_ELEMENT:PASS"
