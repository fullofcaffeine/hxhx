#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIXTURE_ROOT="$ROOT/test/reflaxe_ocaml_reflect_compare_plan"
WORK_DIR="$ROOT/.tmp/reflaxe-ocaml-reflect-compare-plan"
EXPECTED='[ocaml-reflect-compare:unsupported-domain]'

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

expect_unsupported() {
	local name=$1
	local log="$WORK_DIR/$name.log"
	local output="$WORK_DIR/$name-out"

	if haxe \
		-cp "$FIXTURE_ROOT/$name" \
		-main Main \
		--no-output \
		-lib reflaxe.ocaml \
		-D no-traces \
		-D no_traces \
		-D "ocaml_output=$output" >"$log" 2>&1; then
		echo "Expected $name to reject unsupported Reflect.compare operands" >&2
		exit 1
	fi

	if ! grep -Fq "$EXPECTED" "$log"; then
		echo "Missing fail-closed Reflect.compare diagnostic for $name" >&2
		cat "$log" >&2
		exit 1
	fi

	if find "$output" -type f -name '*.ml' -print -quit 2>/dev/null | grep -q .; then
		echo "$name produced OCaml source after its comparison domain was rejected" >&2
		exit 1
	fi
}

expect_unsupported unsupported_bool
expect_unsupported unsupported_dynamic

echo "REFLECT_COMPARE_PLAN_NEGATIVE:PASS"
