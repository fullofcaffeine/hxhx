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

# A secondary Haxe class shares Main.ml with the primary class. Its generated
# method therefore needs the secondary class prefix. A class in its own module
# keeps the normal module-qualified call.
grep -q 'namedvalue_toString' out/Main.ml
grep -q 'SeparateValue.toString' out/Main.ml

echo "SAME_MODULE_TOSTRING_ORACLE_AND_NAMES:PASS"
