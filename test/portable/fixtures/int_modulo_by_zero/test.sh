#!/usr/bin/env bash
set -euo pipefail
# Haxe leaves Int division by zero target-specific. Upstream eval returns NaN,
# which a native 32-bit Int cannot hold, so this fixture's oracle is upstream
# Neko, which throws a catchable exception like the native runtime.
"${HAXE_BIN:-haxe}" -cp src -main Main -neko out/upstream.n
neko out/upstream.n > out/upstream.stdout
diff -u expected.stdout out/upstream.stdout
