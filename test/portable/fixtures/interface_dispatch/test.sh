#!/usr/bin/env bash
set -euo pipefail
haxe contracts.hxml
diff -u expected.stdout <(haxe -cp src -main Main --interp)
echo 'INTERFACE_DISPATCH:PASS'
