#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REQUIREMENTS_FILE="out/ocaml_runtime_requirement_report.json"
REPORT_COPY="$(mktemp)"
MANIFEST_FILE="out/ocaml_artifact_manifest.json"
MANIFEST_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
TAMPER_INSPECTION="$(mktemp)"
NEGATIVE_COMPILE="$(mktemp)"
trap 'rm -f "$REPORT_COPY" "$MANIFEST_COPY" "$INSPECTION_COPY" "$TAMPER_INSPECTION" "$NEGATIVE_COMPILE"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ] || [ ! -f "$REQUIREMENTS_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
	echo "Missing generated exact-catch source, lowering report, runtime-requirement report, or manifest" >&2
	exit 1
fi

node - "$SOURCE_FILE" "$REPORT_FILE" "$REQUIREMENTS_FILE" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
const requirements = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'))
const sha256 = /^sha256:[0-9a-f]{64}$/
const rawSha256 = /^[0-9a-f]{64}$/
const bodyRevision = /^[0-9]+:[0-9a-f]{64}$/

function fail(message) {
	throw new Error(message)
}

if (report.schemaVersion !== 71
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v23'
	|| report.controlCatchModel !== 'typed-ocaml-represented-value-catch-chain-v5'
	|| report.controlCatchCount !== report.controlCatches.length
	|| !sha256.test(report.controlCatchRevision)) {
	fail('unexpected exact-catch report schema, model, inventory, or revision')
}

const allCatches = report.controlCatches
const catches = allCatches.filter(chain =>
	chain.functionId.startsWith('Main|Main|'))
if (allCatches.length !== 19 || catches.length !== 15) {
	fail(`expected 19 sealed catch chains across the program and 15 in Main, got ${allCatches.length}/${catches.length}`)
}
const catchRequirements = requirements.requirements.filter(requirement =>
	requirement.semanticCapability === 'hxhx-runtime:typed-haxe-catch-chain-v1'
	&& allCatches.some(chain => chain.id === requirement.decisionId))
if (catchRequirements.length !== allCatches.length
	|| catchRequirements.some(requirement =>
		requirement.sourceKind !== 'haxe-expression'
		|| requirement.cause !== 'lowering-decision'
		|| requirement.rootModules.join(',') !== 'HxRuntime'
		|| requirement.sourceId !== requirement.decisionId
		|| requirement.id !== `${requirement.decisionId}:runtime:hxhx-runtime:typed-haxe-catch-chain-v1`)) {
	fail('the real catch chains did not each publish one exact HxRuntime requirement')
}
const enumCatchRequirements = requirements.requirements.filter(requirement =>
	requirement.semanticCapability === 'haxe-enum-catch-payload-recovery-v1')
if (enumCatchRequirements.length !== 1
	|| enumCatchRequirements[0].sourceId !== enumCatchRequirements[0].decisionId
	|| enumCatchRequirements[0].subject?.id !== 'haxe.io.Error'
	|| enumCatchRequirements[0].implementationFeature !== 'enum-catch-unbox-or-object'
	|| enumCatchRequirements[0].rootModules.join(',') !== 'HxEnum') {
	fail('the enum catch did not own its exact HxEnum payload-recovery requirement')
}
const independent = catches.filter(chain =>
	chain.functionId.includes('|function|independentAdmission|'))
const independentBool = independent.find(chain => chain.clauses[0]?.semanticTypeId === 'Bool')
const independentFloat = independent.find(chain => chain.clauses[0]?.semanticTypeId === 'Float')
if (independent.length !== 2
	|| independent.some(chain => chain.clauses.length !== 1)
	|| !independentBool
	|| !independentFloat) {
	fail('the neighboring Bool and Float tries were not admitted as independent sealed catch chains')
}

const expected = {
	Int: ['Int', 'int', 'representation:Int:internal-value', 'recover-exact-value', 'exact-runtime-tag'],
	Float: ['Float', 'float', 'representation:Float:internal-value', 'recover-exact-value', 'exact-runtime-tag'],
	Bool: ['Bool', 'bool', 'representation:Bool:internal-value', 'recover-checked-bool', 'exact-runtime-tag'],
	String: ['String', 'string', 'representation:String:internal-value', 'recover-exact-value', 'exact-runtime-tag'],
	Dynamic: [null, 'Obj.t', 'control-representation:Dynamic:runtime-obj-v1', 'preserve-dynamic-carrier', 'match-all'],
	'haxe.io.Error': ['haxe.io.Error', 'haxe-enum-native-variant-carrier-v1:haxe.io.Error', 'control-representation:enum-catch-v1:haxe.io.Error', 'recover-enum-value', 'exact-runtime-tag'],
	'haxe.Exception': [null, 'Haxe_Exception.t', 'control-representation:haxe.Exception:runtime-wrapper-v1', 'preserve-or-wrap-haxe-exception', 'match-haxe-exception']
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
		|| chain.proofId !== 'represented-value-catch-control-v5'
		|| chain.pipelineRevision !== 'ocaml-function-plans-v86'
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
			|| clause.matchPolicy !== shape[4]
			|| !resultPolicies.has(clause.bodyResultPolicy)
			|| clause.effects.join(',') !== 'select-first-matching-clause,bind-catch-variable,execute-catch-body') {
			fail(`catch clause ${clause.id} does not match its sealed source-order decision`)
		}
		if (clause.semanticTypeId === 'Dynamic') {
			if (clause.matchPolicy !== 'match-all' || index !== chain.clauses.length - 1)
				fail(`Dynamic catch ${clause.id} was not the final match-all clause`)
			sawDynamic = true
		} else if ((clause.semanticTypeId !== 'haxe.Exception' && clause.matchPolicy !== 'exact-runtime-tag') || sawDynamic) {
			fail(`exact catch ${clause.id} appeared after Dynamic or used a non-exact predicate`)
		}
		ids.add(clause.id)
	}
}
const eofCatches = allCatches.filter(chain => chain.clauses.some(clause => clause.semanticTypeId === 'haxe.io.Eof'))
if (eofCatches.length !== 4
	|| eofCatches.some(chain => chain.clauses.length !== 1
		|| chain.clauses[0].outputCarrierTypeId !== 't'
		|| chain.clauses[0].outputRepresentationId !== 'representation:haxe.io.Eof:internal-value'
		|| chain.clauses[0].runtimeTag !== 'haxe.io.Eof'
		|| chain.clauses[0].conversion !== 'recover-nominal-value'
		|| chain.clauses[0].nominalRepresentation?.targetModuleName !== 'Haxe_io_Eof'
		|| chain.clauses[0].nominalRepresentation?.targetTypeName !== 't'
		|| !sha256.test(chain.clauses[0].nominalRepresentation?.layoutRevision || ''))) {
	fail('the four portable-library Eof catches did not reuse one sealed generated class layout')
}
const blockedNonEmpty = report.controlAdmissions.flatMap(admission => admission.catches)
	.filter(catchAdmission => catchAdmission.status === 'blocked'
		&& !catchAdmission.blockers.every(blocker => blocker.code === 'catch-chain-empty'))
if (blockedNonEmpty.length !== 0)
	fail(`non-empty catch occurrences remain blocked after the hard cut: ${blockedNonEmpty.map(entry => entry.occurrenceId).join(',')}`)
if (independentBool.tryBodyResultPolicy !== 'discard-completed-value-to-unit'
	|| independentBool.clauses[0].bodyResultPolicy !== 'discard-completed-value-to-unit') {
	fail('the Void try with value-producing branches did not seal its unit-discard policy')
}
if (independentFloat.tryBodyResultPolicy !== 'preserve-typed-result'
	|| independentFloat.clauses[0].bodyResultPolicy !== 'discard-completed-value-to-unit') {
	fail('the Float try did not preserve its non-completing throw while discarding its completed assignment branch')
}

const callback = catches.find(chain => chain.functionId.includes('|function|capture|'))
if (!callback
	|| callback.tryBodyResultPolicy !== 'discard-completed-value-to-unit'
	|| callback.clauses.length !== 2
	|| callback.clauses.some(clause => clause.bodyResultPolicy !== 'discard-completed-value-to-unit')) {
	fail('the Void callback catch did not discard every completed branch value')
}
const directVoid = catches.find(chain => chain.functionId.includes('|function|discardBoolFromCatch|'))
if (!directVoid
	|| directVoid.tryBodyResultPolicy !== 'discard-completed-value-to-unit'
	|| directVoid.clauses.some(clause => clause.bodyResultPolicy !== 'discard-completed-value-to-unit')) {
	fail('the direct Void catch did not discard its Boolean branch values')
}
const valueProducing = catches.find(chain => chain.functionId.includes('|function|valueProducingCatch|'))
if (!valueProducing
	|| valueProducing.tryBodyResultPolicy !== 'preserve-typed-result'
	|| valueProducing.clauses.some(clause => clause.bodyResultPolicy !== 'preserve-typed-result')) {
	fail('the non-Void catch stopped preserving its selected String value')
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
const callbackStart = source.indexOf('let capture =')
const callbackEnd = source.indexOf('\nlet callbackVoidResult =', callbackStart)
const callbackBody = source.slice(callbackStart, callbackEnd)
if (callbackStart < 0
	|| callbackEnd < 0
	|| !callbackBody.includes('ignore (HxArray.push')) {
	fail('the Void callback catch did not discard Array.push\'s generated integer result')
}
const typedVoidStart = source.indexOf('let captureProductionTypes =')
const typedVoidEnd = source.indexOf('\nlet typedVoidResult =', typedVoidStart)
const typedVoidBody = source.slice(typedVoidStart, typedVoidEnd)
if (typedVoidStart < 0
	|| typedVoidEnd < 0
	|| !typedVoidBody.includes('ignore (HxArray.push')
	|| !typedVoidBody.includes('HxEnum.unbox_or_obj "haxe.io.Error"')) {
	fail('the enum-backed Void catch did not preserve its sealed payload recovery and branch-result policy')
}
const directVoidStart = source.indexOf('let discardBoolFromCatch =')
const directVoidEnd = source.indexOf('\nlet directVoidResult =', directVoidStart)
const directVoidBody = source.slice(directVoidStart, directVoidEnd)
if (directVoidStart < 0
	|| directVoidEnd < 0
	|| !directVoidBody.includes('ignore (HxArray.remove')) {
	fail('the direct Void catch did not discard Array.remove\'s generated Boolean result')
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
if (report.schemaVersion !== 45
	|| report.summary.valid !== true
	|| report.summary.controlCatchCount !== report.lowering.controlCatches.length
	|| report.lowering.controlCatches.length !== 19
	|| report.lowering.scope !== 'typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose all 19 validated primitive, enum, class, wrapper, and Dynamic catch chains')
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

node - "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const clause = report.controlCatches.flatMap(chain => chain.clauses)
	.find(candidate => candidate.semanticTypeId === 'haxe.io.Error')
if (!clause)
	throw new Error('missing enum catch clause to corrupt')
clause.outputCarrierTypeId = 'Obj.t'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision "$REPORT_FILE"

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$TAMPER_INSPECTION" 2>&1; then
	echo "Public inspection accepted an enum catch with a corrupt native carrier" >&2
	exit 1
fi
if ! grep -q "Enum control catch clause" "$TAMPER_INSPECTION"; then
	echo "Public inspection rejected the corrupt enum catch without an actionable reason" >&2
	cat "$TAMPER_INSPECTION" >&2
	exit 1
fi
cp "$REPORT_COPY" "$REPORT_FILE"

node - "$REPORT_FILE" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const clause = report.controlCatches.flatMap(chain => chain.clauses)
	.find(candidate => candidate.semanticTypeId === 'haxe.io.Eof')
if (!clause?.nominalRepresentation)
	throw new Error('missing nominal Eof catch clause to corrupt')
clause.nominalRepresentation.targetTypeName = 'stale_t'
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision "$REPORT_FILE"

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$TAMPER_INSPECTION" 2>&1; then
	echo "Public inspection accepted an Eof catch with a stale nominal layout" >&2
	exit 1
fi
if ! grep -q "Monomorphic-class control catch clause" "$TAMPER_INSPECTION"; then
	echo "Public inspection rejected the stale nominal catch without an actionable reason" >&2
	cat "$TAMPER_INSPECTION" >&2
	exit 1
fi
cp "$REPORT_COPY" "$REPORT_FILE"
cp "$MANIFEST_COPY" "$MANIFEST_FILE"

if haxe build.hxml -D exact_catch_unrepresented_negative >"$NEGATIVE_COMPILE" 2>&1; then
	echo "A non-empty generic exception catch reached target syntax without a sealed chain" >&2
	exit 1
fi
if ! grep -q 'non-empty catch.*without a sealed chain' "$NEGATIVE_COMPILE"; then
	echo "The unsupported catch failed without identifying the hard-cut boundary" >&2
	cat "$NEGATIVE_COMPILE" >&2
	exit 1
fi
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The rejected unsupported catch published a lowering report" >&2
	exit 1
fi

echo "REFLAXE_OCAML_EXACT_CATCH_CONTROL_FIXTURE:PASS chains=19"
