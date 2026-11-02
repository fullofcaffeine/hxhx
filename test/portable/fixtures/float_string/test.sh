#!/usr/bin/env bash
set -euo pipefail

# Installed Haxe 4.3.7 is the independent behavior oracle. The portable runner
# has already compared the native executable with expected.stdout; this check
# keeps expected.stdout equal to what upstream eval prints.
oracle_dir="$(mktemp -d)"
trap 'rm -rf "$oracle_dir"' EXIT
haxe -cp src --run Main >"$oracle_dir/eval.stdout"
diff -u expected.stdout "$oracle_dir/eval.stdout"
echo "FLOAT_STRING_UPSTREAM_TEXT:PASS"
