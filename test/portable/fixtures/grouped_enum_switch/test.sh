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

if grep -q '^ *| _ ->' out/Main.ml; then
	echo "An exhaustive grouped enum switch still contains a wildcard branch" >&2
	exit 1
fi
grep -Eq '\| A \| B ->' out/Main.ml
grep -Eq '\| C \| D ->' out/Main.ml

echo "GROUPED_ENUM_SWITCH_ORACLE_AND_PATTERNS:PASS"
