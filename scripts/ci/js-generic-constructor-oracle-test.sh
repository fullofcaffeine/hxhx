#!/usr/bin/env bash
set -euo pipefail

# Black-box Haxe 4.3.7 behavior check for generic constructor syntax.
# The source is repo-owned: upstream supplies only the compiler behavior oracle.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"

if [ "$($HAXE_BIN --version)" != "4.3.7" ]; then
	echo "Generic-constructor oracle requires Haxe 4.3.7." >&2
	exit 2
fi

mkdir -p "$ROOT/.tmp"
cd "$ROOT"
"$HAXE_BIN" test/m14_js_generic_constructor_oracle.hxml
node .tmp/m14_js_generic_constructor_oracle.js

echo "JS_GENERIC_CONSTRUCTOR_ORACLE:PASS"
