#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
if [ ! -f "$source_file" ]; then
	echo "Missing generated generic identity source" >&2
	exit 1
fi

if ! grep -Eq '^let identity = fun value -> value$' "$source_file"; then
	echo "The generic identity definition is not one inferred OCaml polymorphic function" >&2
	exit 1
fi

if grep -Eq 'identity[[:space:]]+\(?Obj\.(magic|repr|obj)' "$source_file"; then
	echo "A generic identity call changed its concrete carrier through Obj" >&2
	exit 1
fi

node - <<'NODE'
const report = require('./out/ocaml_lowering_report.json')
if (report.schemaVersion !== 86
	|| report.callModel !== 'typed-ocaml-directional-call-boundary-v31') {
	throw new Error('The generic identity fixture uses a stale lowering contract')
}
const calls = report.calls.filter(call =>
	call.kind === 'direct-static-generic-identity'
	&& call.sourceModuleId === 'Main'
	&& call.sourceFieldName === 'identity')
if (calls.length !== 2) {
	throw new Error(`Expected two sealed generic identity calls, found ${calls.length}`)
}
const carriers = calls
	.map(call => `${call.arguments[0].inputSemanticTypeId}:${call.arguments[0].inputCarrierTypeId}->${call.result.outputCarrierTypeId}`)
	.sort()
if (carriers.join(',') !== 'Int:int->int,String:string->string') {
	throw new Error(`Unexpected generic identity carriers: ${carriers.join(',')}`)
}
for (const call of calls) {
	if (call.proofId !== 'direct-static-generic-identity-v1'
		|| call.pipelineRevision !== 'ocaml-function-plans-v109'
		|| call.arguments[0].conversion !== 'identity'
		|| call.result.conversion !== 'identity') {
		throw new Error(`Generic identity call ${call.id} lacks its typed carrier proof`)
	}
}
NODE

if [ "$(haxe --version)" != "4.3.7" ]; then
	echo "This oracle fixture requires upstream Haxe 4.3.7" >&2
	exit 1
fi

oracle_stdout="$(mktemp)"
trap 'rm -f "$oracle_stdout"' EXIT
haxe -cp src -main Main --interp >"$oracle_stdout"
diff -u expected.stdout "$oracle_stdout"

echo "GENERIC_IDENTITY_CARRIER_ORACLE_AND_SOURCE_SHAPE:PASS"
