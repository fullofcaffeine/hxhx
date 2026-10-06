#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"

upstream_output="$("${HAXE_BIN:-haxe}" -cp src -main Main --interp)"
diff -u expected.stdout <(printf '%s\n' "$upstream_output")

if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated entrypoint source or lowering report" >&2
	exit 1
fi

if ! grep -Eq 'ignore \(GeneratedEntrypoint\.init \(\)\);' "$source_file" \
	|| ! grep -Fq 'HxRuntime.hx_null' "$source_file"; then
	echo "The Dynamic local did not run the sealed Void call and then produce Haxe null" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs');
const assert = require('node:assert/strict');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const calls = report.calls ?? [];
const matches = calls.filter(call =>
	call.calleeId === 'GeneratedEntrypoint|GeneratedEntrypoint::init'
	&& call.resultKind === 'effect-only-void'
	&& call.resultMaterialization === 'untyped-void-as-dynamic-null');
assert.equal(matches.length, 2, 'method and initializer each need one effect-only call');
const initializerOwner = 'standalone:field-initializer:static:StaticEntrypoint|StaticEntrypoint::result';
assert.equal(matches.filter(call => call.functionId === initializerOwner).length, 1,
	'the static call must belong to its own initializer');
assert.equal(matches.filter(call => !call.functionId.startsWith('standalone:')).length, 1,
	'the local call must retain its function owner');
for (const call of matches) {
	assert(report.runtimeRequirements.some(requirement => requirement.decisionId === call.id
		&& requirement.rootModules.includes('HxRuntime')), 'the call lost its null runtime requirement');
}
NODE
