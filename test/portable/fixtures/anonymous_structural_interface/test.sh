#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
(cd ../../../.. && "${HAXE_BIN:-haxe}" test/reflaxe_ocaml_method_dispatch_runtime_test.hxml)
echo "ANONYMOUS_STRUCTURAL_INTERFACE:PASS"
