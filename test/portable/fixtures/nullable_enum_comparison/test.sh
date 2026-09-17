#!/usr/bin/env bash
set -euo pipefail

# Keep upstream behavior as a separate observer from generated OCaml output.
# The portable runner calls this script from the fixture directory.
upstream_output="$(mktemp)"
trap 'rm -f "$upstream_output"' EXIT
"${HAXE_BIN:-haxe}" -cp src -main Main --interp > "$upstream_output"
diff -u expected.stdout "$upstream_output"
