#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REPORT_COPY="$(mktemp)"
MANIFEST_FILE="out/ocaml_artifact_manifest.json"
MANIFEST_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
TAMPER_INSPECTION="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$MANIFEST_COPY" "$INSPECTION_COPY" "$TAMPER_INSPECTION"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
	echo "Missing generated exact-catch source or lowering report" >&2
	exit 1
fi

node - "$SOURCE_FILE" "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const sha256 = /^sha256:[0-9a-f]{64}$/
const rawSha256 = /^[0-9a-f]{64}$/
const bodyRevision = /^[0-9]+:[0-9a-f]{64}$/

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 64
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v20'
	|| report.controlCatchModel !== 'typed-ocaml-represented-value-catch-chain-v3'
	|| report.controlCatchCount !== report.controlCatches.length
	|| !sha256.test(report.controlCatchRevision)) {
	fail('unexpected exact-catch report schema, model, inventory, or revision')
}

const catches = report.controlCatches.filter(chain =>
	chain.functionId.startsWith('Main|Main|'))
if (catches.length !== 10) {
	fail(`expected 10 exact primitive/Dynamic catch chains, got ${catches.length}`)
}
if (catches.some(chain =>
	chain.functionId.includes('|function|independentAdmission|')
	&& chain.clauses.some(clause => clause.semanticTypeId === 'Float'))) {
	fail('the unsupported Float catch was partially admitted to the exact catch model')
}
const independent = catches.filter(chain =>
	chain.functionId.includes('|function|independentAdmission|'))
if (independent.length !== 1
	|| independent[0].clauses.length !== 1
	|| independent[0].clauses[0].semanticTypeId !== 'Bool') {
	fail('the supported try beside an unsupported Float try was not admitted independently')
}

const expected = {
	Int: ['Int', 'int', 'representation:Int:internal-value', 'recover-exact-value'],
	Bool: ['Bool', 'bool', 'representation:Bool:internal-value', 'recover-checked-bool'],
	String: ['String', 'string', 'representation:String:internal-value', 'recover-exact-value'],
	Dynamic: [null, 'Obj.t', 'control-representation:Dynamic:runtime-obj-v1', 'preserve-dynamic-carrier']
}
const resultPolicies = new Set(['preserve-typed-result', 'discard-completed-value-to-unit'])
const ids = new Set()
for (const chain of catches) {
	if (ids.has(chain.id)
		|| chain.inputChannels.join(',') !== 'haxe-exception-signal,target-native-exception'
		|| chain.haxeUnmatchedPolicy !== 'rethrow-haxe-exception-signal'
		|| chain.targetNativeUnmatchedPolicy !== 'reraise-target-native-exception'
		|| chain.privateControlPolicy !== 'propagate-private-control-signals'
		|| chain.targetNativeRuntimeTags.join(',') !== 'OcamlExn'
		|| chain.runtimeCapabilityId !== 'hxhx-runtime:typed-haxe-catch-chain-v1'
		|| !resultPolicies.has(chain.tryBodyResultPolicy)
		|| chain.proofId !== 'represented-value-catch-control-v3'
		|| chain.pipelineRevision !== 'ocaml-function-plans-v74'
		|| chain.profileEligibility.join(',') !== 'metal,portable'
		|| !rawSha256.test(chain.programRevision)
		|| !bodyRevision.test(chain.bodyRevision)
		|| !chain.reason
		|| !chain.proofClaim
		|| !chain.source.file
		|| chain.source.min < 0
		|| chain.source.max < chain.source.min) {
		fail(`catch chain ${chain.id} has incomplete ownership or lifecycle metadata`)
	}
	ids.add(chain.id)
	let sawDynamic = false
	for (let index = 0; index < chain.clauses.length; index++) {
		const clause = chain.clauses[index]
		const shape = expected[clause.semanticTypeId]
		if (!shape
			|| clause.order !== index
			|| ids.has(clause.id)
			|| clause.functionId !== chain.functionId
			|| clause.programRevision !== chain.programRevision
			|| clause.bodyRevision !== chain.bodyRevision
			|| clause.pipelineRevision !== chain.pipelineRevision
			|| clause.proofId !== chain.proofId
			|| clause.signalCarrierTypeId !== 'Obj.t'
			|| clause.runtimeTag !== shape[0]
			|| clause.outputCarrierTypeId !== shape[1]
			|| clause.outputRepresentationId !== shape[2]
			|| clause.conversion !== shape[3]
			|| !resultPolicies.has(clause.bodyResultPolicy)
			|| clause.effects.join(',') !== 'select-first-matching-clause,bind-catch-variable,execute-catch-body') {
			fail(`catch clause ${clause.id} does not match its sealed source-order decision`)
		}
		if (clause.semanticTypeId === 'Dynamic') {
			if (clause.matchPolicy !== 'match-all' || index !== chain.clauses.length - 1)
				fail(`Dynamic catch ${clause.id} was not the final match-all clause`)
			sawDynamic = true
		} else if (clause.matchPolicy !== 'exact-runtime-tag' || sawDynamic) {
			fail(`exact catch ${clause.id} appeared after Dynamic or used a non-exact predicate`)
		}
		ids.add(clause.id)
	}
}
if (independent[0].tryBodyResultPolicy !== 'discard-completed-value-to-unit'
	|| independent[0].clauses[0].bodyResultPolicy !== 'discard-completed-value-to-unit') {
	fail('the Void try with value-producing branches did not seal its unit-discard policy')
}

const orderedStart = source.indexOf('let orderedBool =')
const orderedEnd = source.indexOf('\nlet exactFirst =', orderedStart)
const orderedBody = source.slice(orderedStart, orderedEnd)
if (orderedStart < 0
	|| orderedEnd < 0
	|| orderedBody.indexOf('HxRuntime.tags_has') < 0
	|| orderedBody.indexOf('"Int"') > orderedBody.indexOf('"Bool"')
	|| orderedBody.indexOf('"Bool"') > orderedBody.indexOf('else if true')
	|| !orderedBody.includes('HxRuntime.unbox_bool_or_obj')) {
	fail('generated ordered catch syntax did not mechanically preserve Int, Bool, Dynamic order and Bool binding')
}
if (!source.includes('HxRuntime.Hx_return')
	|| !source.includes('HxRuntime.Hx_break -> raise (HxRuntime.Hx_break)')
	|| !source.includes('HxRuntime.Hx_continue -> raise (HxRuntime.Hx_continue)')
	|| !source.includes('HxRuntime.Hx_exception')
	|| !source.includes('| __exn_')) {
	fail('generated catch syntax does not preserve both exception channels and private controls')
}
const nativeStart = source.indexOf('let targetNativeFailure =')
const nativeEnd = source.indexOf('\nlet main =', nativeStart)
const nativeBody = source.slice(nativeStart, nativeEnd)
if (nativeStart < 0
	|| nativeEnd < 0
	|| !nativeBody.includes('| __exn_')
	|| !/Obj\.repr __exn_[0-9]+/.test(nativeBody)
	|| !nativeBody.includes('"native=dynamic"')) {
	fail('target-native exceptions did not enter the sealed Dynamic catch chain')
}
NODE

cp "$REPORT_FILE" "$REPORT_COPY"
cp "$MANIFEST_FILE" "$MANIFEST_COPY"
haxe build.hxml
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The exact same typed program produced a different catch-control report" >&2
	diff -u "$REPORT_COPY" "$REPORT_FILE" >&2 || true
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$INSPECTION_COPY"

node - "$INSPECTION_COPY" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 41
	|| report.summary.valid !== true
	|| report.summary.controlCatchCount !== report.lowering.controlCatches.length
	|| report.lowering.controlCatches.length !== 10
	|| report.lowering.scope !== 'typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the 10 validated catch-chain decisions')
}
NODE

node - "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const chain = report.controlCatches.find(candidate => candidate.clauses.length > 1)
if (!chain)
	throw new Error('missing multi-clause catch chain to corrupt')
chain.clauses[0].bodyResultPolicy = 'infer-in-printer'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision "$REPORT_FILE"

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$TAMPER_INSPECTION" 2>&1; then
	echo "Public inspection accepted a catch chain with corrupt result handling" >&2
	exit 1
fi
if ! grep -q "Control catch clause" "$TAMPER_INSPECTION"; then
	echo "Public inspection rejected the corrupt catch chain without an actionable reason" >&2
	cat "$TAMPER_INSPECTION" >&2
	exit 1
fi
cp "$REPORT_COPY" "$REPORT_FILE"
cp "$MANIFEST_COPY" "$MANIFEST_FILE"

echo "REFLAXE_OCAML_EXACT_CATCH_CONTROL_FIXTURE:PASS chains=10"
