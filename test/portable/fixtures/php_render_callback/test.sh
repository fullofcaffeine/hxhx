#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -cp ../../../../packages/hxhx-core/src -main PhpRenderCallbackFixture --interp)
