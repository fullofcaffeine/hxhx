#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-enum-dynamic-oracle.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

HAXE_VERSION="$(haxe -version)"
if [[ "$HAXE_VERSION" != "4.3.7" ]]; then
	echo "Expected the Haxe 4.3.7 behavior oracle, found $HAXE_VERSION." >&2
	exit 1
fi

# Compile the same Haxe program through stock targets before comparing hxhx.
#
# This fixture is specifically about source-language behavior: constant enum
# constructors compare as the same Dynamic value, payload constructors remain
# distinct, and typed catches recover both forms. Running eval and JavaScript
# proves the expected output is not inferred from generated OCaml. Neko is
# included when its runner is installed, so the fixture gains another stock
# runtime oracle without making that optional tool a prerequisite.
haxe -cp "$SCRIPT_DIR/src" -main Main --interp > "$TMP_DIR/interp.stdout"
diff -u "$SCRIPT_DIR/expected.stdout" "$TMP_DIR/interp.stdout"

haxe -cp "$SCRIPT_DIR/src" -main Main -js "$TMP_DIR/main.js"
node "$TMP_DIR/main.js" > "$TMP_DIR/js.stdout"
diff -u "$SCRIPT_DIR/expected.stdout" "$TMP_DIR/js.stdout"

if command -v neko >/dev/null 2>&1; then
	haxe -cp "$SCRIPT_DIR/src" -main Main -neko "$TMP_DIR/main.n"
	neko "$TMP_DIR/main.n" > "$TMP_DIR/neko.stdout"
	diff -u "$SCRIPT_DIR/expected.stdout" "$TMP_DIR/neko.stdout"
fi

echo "HAXE_4_3_7_ENUM_DYNAMIC_ORACLE:PASS"
