#!/usr/bin/env bash
set -euo pipefail

if [ "$(haxe --version)" != "4.3.7" ]; then
	echo "This behavior fixture requires upstream Haxe 4.3.7" >&2
	exit 1
fi

oracle_stdout="$(mktemp)"
trap 'rm -f "$oracle_stdout"' EXIT
haxe -cp src -main Main --interp >"$oracle_stdout"
diff -u expected.stdout "$oracle_stdout"

if ! grep -q 'HxType.getClass' out/Main.ml; then
	echo "The generated program did not exercise the runtime Type.getClass boundary" >&2
	exit 1
fi

echo "TYPE_GETCLASS_DYNAMIC_TOKEN_ORACLE:PASS"
