#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
SOURCE_FILE="out/Main.ml"
REPORT_FILE="out/ocaml_lowering_report.json"
REPORT_COPY="$(mktemp)"
INSPECTION_COPY="$(mktemp)"
INVALID_NOMINAL_ROOT="$(mktemp -d)"
INVALID_ARRAY_ROOT="$(mktemp -d)"
INVALID_LITERAL_ROOT="$(mktemp -d)"
INVALID_ADMISSION_ROOT="$(mktemp -d)"
INVALID_RESULT_ROOT="$(mktemp -d)"
trap 'rm -f "$REPORT_COPY" "$INSPECTION_COPY"; rm -rf "$INVALID_NOMINAL_ROOT" "$INVALID_ARRAY_ROOT" "$INVALID_LITERAL_ROOT" "$INVALID_ADMISSION_ROOT" "$INVALID_RESULT_ROOT"' EXIT

if [ ! -f "$SOURCE_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
	echo "Missing generated early-return source or lowering report" >&2
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

if (!Array.isArray(report.controlAdmissions)) {
	fail('the lowering report cannot distinguish a blocked control family from a function with no control transfer')
}

if (report.schemaVersion !== 83
	|| report.controlModel !== 'typed-ocaml-function-loop-throw-and-catch-control-v25'
	|| report.controlAdmissionModel !== 'typed-ocaml-control-admission-v1'
	|| report.controlTargetModel !== 'typed-ocaml-lexical-loop-target-v1'
	|| report.functionResultBoundaryModel !== 'typed-ocaml-function-result-boundary-v2'
	|| report.controlCount !== report.controls.length
	|| report.controlAdmissionCount !== report.controlAdmissions.length
	|| report.controlTargetCount !== report.controlTargets.length
	|| report.functionResultBoundaryCount !== report.functionResultBoundaries.length
	|| !sha256.test(report.controlRevision)
	|| !sha256.test(report.controlAdmissionRevision)
	|| !sha256.test(report.controlTargetRevision)
	|| !sha256.test(report.functionResultBoundaryRevision)) {
	fail('unexpected function-result or function/loop control report schema, model, inventory, or revision')
}

function familyFor(admission, family) {
	return admission?.families?.find(entry => entry.family === family)
}

const admittedParse = report.controlAdmissions.find(admission =>
	admission.functionId.includes('haxe.NativeStackTrace|NativeStackTrace|static|function|parseFileLine|'))
const admittedParseReturn = familyFor(admittedParse, 'return')
const admittedParseResult = report.functionResultBoundaries.find(boundary =>
	boundary.functionId === admittedParse?.functionId)
if (admittedParseReturn?.status !== 'admitted'
	|| admittedParseReturn.occurrenceCount !== 4
	|| admittedParseReturn.decisionCount !== 4
	|| admittedParseReturn.blockers.length !== 0
	|| admittedParseResult?.source !== 'static-nullable-anonymous-declaration'
	|| admittedParseResult.callableBoundaryId != null
	|| admittedParseResult.anonymousStructure?.semanticTypeId !== 'anonymous{file:String,line:Int}'
	|| admittedParseResult.result?.inputCarrierTypeId !== 'Obj.t'
	|| admittedParseResult.result?.outputCarrierTypeId !== 'Obj.t'
	|| admittedParseResult.proofId !== 'static-nullable-anonymous-function-result-v1'
	|| report.callableBoundaries.some(boundary => boundary.functionId === admittedParse.functionId)) {
	fail('NativeStackTrace.parseFileLine did not receive its result-only nullable anonymous-object boundary')
}
const admittedBranch = report.controlAdmissions.find(admission =>
	admission.functionId.includes('Main|Main|static|function|branch|'))
const unusedPrint = report.controlAdmissions.find(admission =>
	admission.functionId.includes('Main|Main|static|function|printLine|'))
const hexValue = report.controlAdmissions.find(admission =>
	admission.functionId.includes('StringTools|StringTools|static|function|_hexValue|'))
const hexValueResult = report.functionResultBoundaries.find(boundary =>
	boundary.functionId.includes('StringTools|StringTools|static|function|_hexValue|'))
const declarationOnlyResults = report.functionResultBoundaries.filter(boundary =>
	boundary.source === 'static-inline-exact-int-declaration')
const instanceExactIntResults = report.functionResultBoundaries.filter(boundary =>
	boundary.source === 'non-generic-instance-exact-int-declaration')
if (familyFor(admittedBranch, 'return')?.status !== 'admitted'
	|| familyFor(unusedPrint, 'return')?.status !== 'not-needed') {
	fail('the control admission inventory conflated admitted, blocked, and unused return families')
}
if (familyFor(hexValue, 'return')?.status !== 'admitted'
	|| familyFor(hexValue, 'return')?.occurrenceCount !== 3
	|| familyFor(hexValue, 'return')?.decisionCount !== 3) {
	fail('StringTools._hexValue did not receive its function-owned exact-Int result boundary')
}
if (hexValueResult?.source !== 'static-inline-exact-int-declaration'
	|| hexValueResult.callableBoundaryId != null
	|| hexValueResult.sourceModuleId !== 'StringTools'
	|| hexValueResult.sourceTypeName !== 'StringTools'
	|| hexValueResult.sourceFieldName !== '_hexValue'
	|| hexValueResult.resultKind !== 'value'
	|| hexValueResult.result?.inputSemanticTypeId !== 'Int'
	|| hexValueResult.result?.inputCarrierTypeId !== 'int'
	|| hexValueResult.result?.inputRepresentationId !== 'representation:Int:internal-value'
	|| hexValueResult.result?.outputSemanticTypeId !== 'Int'
	|| hexValueResult.result?.outputCarrierTypeId !== 'int'
	|| hexValueResult.result?.outputRepresentationId !== 'representation:Int:internal-value'
	|| hexValueResult.result?.conversion !== 'identity'
	|| hexValueResult.proofId !== 'static-inline-exact-int-function-result-v1'
	|| declarationOnlyResults.length !== 1
	|| declarationOnlyResults[0]?.id !== hexValueResult.id
	|| report.callableBoundaries.some(boundary => boundary.functionId === hexValueResult.functionId)) {
	fail('StringTools._hexValue result ownership accidentally admitted a callable receiver, argument, or call boundary')
}

const stdioReadBytes = report.controlAdmissions.find(admission =>
	admission.functionId.includes('sys.io.Stdio|OcamlStdioInput|instance|function|readBytes|'))
const stdioWriteBytes = report.controlAdmissions.find(admission =>
	admission.functionId.includes('sys.io.Stdio|OcamlStdioOutput|instance|function|writeBytes|'))
const stdioWriteString = report.controlAdmissions.find(admission =>
	admission.functionId.includes('sys.io.Stdio|OcamlStdioOutput|instance|function|writeString|'))
if (instanceExactIntResults.length !== 2) {
	fail(`expected the two concrete stdio instance Int results, got ${instanceExactIntResults.length}`)
}
for (const [name, admission] of [['readBytes', stdioReadBytes], ['writeBytes', stdioWriteBytes]]) {
	const result = report.functionResultBoundaries.find(boundary => boundary.functionId === admission?.functionId)
	if (familyFor(admission, 'return')?.status !== 'admitted'
		|| familyFor(admission, 'return')?.occurrenceCount !== 1
		|| familyFor(admission, 'return')?.decisionCount !== 1
		|| result?.source !== 'non-generic-instance-exact-int-declaration'
		|| result.callableBoundaryId != null
		|| result.resultKind !== 'value'
		|| result.result?.inputSemanticTypeId !== 'Int'
		|| result.result?.inputCarrierTypeId !== 'int'
		|| result.result?.inputRepresentationId !== 'representation:Int:internal-value'
		|| result.result?.outputSemanticTypeId !== 'Int'
		|| result.result?.outputCarrierTypeId !== 'int'
		|| result.result?.outputRepresentationId !== 'representation:Int:internal-value'
		|| result.result?.conversion !== 'identity'
		|| result.proofId !== 'non-generic-instance-exact-int-function-result-v1'
		|| report.callableBoundaries.some(boundary => boundary.functionId === admission.functionId)) {
		fail(`OcamlStdio ${name} did not receive an exact-Int result without receiver, argument, or call admission`)
	}
}
const stdioWriteStringResult = report.functionResultBoundaries.find(boundary =>
	boundary.functionId === stdioWriteString?.functionId)
if (familyFor(stdioWriteString, 'return')?.status !== 'admitted'
	|| familyFor(stdioWriteString, 'return')?.occurrenceCount !== 1
	|| familyFor(stdioWriteString, 'return')?.decisionCount !== 1
	|| stdioWriteStringResult?.source !== 'non-generic-instance-effect-only-void-declaration'
	|| stdioWriteStringResult.callableBoundaryId != null
	|| stdioWriteStringResult.resultKind !== 'effect-only-void'
	|| stdioWriteStringResult.result != null
	|| stdioWriteStringResult.proofId !== 'non-generic-instance-effect-only-void-function-result-v1'
	|| report.callableBoundaries.some(boundary => boundary.functionId === stdioWriteString.functionId)) {
	fail('OcamlStdio writeString did not receive a payloadless result without receiver, argument, or call admission')
}
const stdioReadBytesThrow = familyFor(stdioReadBytes, 'throw')
const eofRepresentation = report.representations.find(item =>
	item.id === 'representation:haxe.io.Eof:internal-value')
const eofThrows = report.controls.filter(control =>
	control.functionId === stdioReadBytes?.functionId
	&& control.kind === 'throw'
	&& control.payload?.inputSemanticTypeId === 'haxe.io.Eof')
const eofThrow = eofThrows[0]
const eofPayload = eofThrow?.payload
const eofNominal = eofPayload?.nominalRepresentation
if (stdioReadBytesThrow?.status !== 'admitted'
	|| stdioReadBytesThrow.occurrenceCount !== 1
	|| stdioReadBytesThrow.decisionCount !== 1
	|| stdioReadBytesThrow.blockers.length !== 0
	|| eofThrows.length !== 1
	|| eofThrow.functionId !== stdioReadBytes.functionId
	|| eofThrow.source.file !== 'packages/reflaxe.ocaml/std/ocaml/_std/sys/io/Stdio.hx'
	|| eofThrow.source.max < eofThrow.source.min
	|| eofThrow.effect !== 'raise-haxe-value'
	|| eofThrow.targetKind !== 'haxe-exception-channel'
	|| eofThrow.targetId !== 'control-target:haxe-exception-channel:v1'
	|| eofThrow.mechanism !== 'runtime-typed-haxe-exception-signal'
	|| eofThrow.runtimeCapabilityId !== 'hxhx-runtime:typed-haxe-exception-signal-v1'
	|| eofThrow.runtimeTags.join(',') !== 'Dynamic'
	|| eofThrow.runtimeTagPolicy !== 'merge-dynamic-with-exact-runtime-value'
	|| eofThrow.profileEligibility.join(',') !== 'metal,portable'
	|| eofThrow.proofId !== 'exact-monomorphic-class-throw-control-v1'
	|| eofPayload == null
	|| eofRepresentation == null
	|| eofPayload.inputSemanticTypeId !== 'haxe.io.Eof'
	|| eofPayload.inputCarrierTypeId !== 't'
	|| eofPayload.inputRepresentationId !== eofRepresentation.id
	|| eofPayload.representationRevision !== eofRepresentation.revision
	|| eofPayload.outputSemanticTypeId !== 'haxe.io.Eof'
	|| eofPayload.outputCarrierTypeId !== 't'
	|| eofPayload.outputRepresentationId !== eofRepresentation.id
	|| eofPayload.signalCarrierTypeId !== 'Obj.t'
	|| eofPayload.conversion !== 'box-nominal-throw-carrier'
	|| eofPayload.proofId !== eofThrow.proofId
	|| eofRepresentation.semanticTypeId !== 'haxe.io.Eof'
	|| eofRepresentation.carrierTypeId !== 't'
	|| eofRepresentation.nominalTargetModuleName !== 'Haxe_io_Eof'
	|| eofRepresentation.nominalTargetTypeName !== 't'
	|| eofRepresentation.boxingPolicy !== 'nullable-nominal-record-carrier'
	|| eofRepresentation.nullPolicy !== 'runtime-sentinel'
	|| eofRepresentation.profileEligibility.join(',') !== 'metal,portable'
	|| !sha256.test(eofRepresentation.nominalLayoutRevision)
	|| eofRepresentation.proof?.id !== `whole-program-monomorphic-nominal-record-v1:${eofRepresentation.nominalLayoutRevision}`
	|| eofNominal?.targetModuleName !== eofRepresentation.nominalTargetModuleName
	|| eofNominal?.targetTypeName !== eofRepresentation.nominalTargetTypeName
	|| eofNominal?.layoutRevision !== eofRepresentation.nominalLayoutRevision
	|| eofNominal?.representationProofId !== eofRepresentation.proof?.id
	|| familyFor(stdioWriteBytes, 'throw')?.status !== 'not-needed') {
	fail('OcamlStdio readBytes did not retain its exact Eof throw while writeBytes remained throw-free')
}

const stringToolsSource = fs.readFileSync('out/StringTools.ml', 'utf8')
const hexValueStart = stringToolsSource.indexOf('let _hexValue =')
const hexValueEnd = stringToolsSource.indexOf('\nlet ', hexValueStart + 1)
const hexValueBody = stringToolsSource.slice(hexValueStart, hexValueEnd)
if (hexValueStart < 0
	|| hexValueEnd < 0
	|| !hexValueBody.includes('HxRuntime.Hx_return')
	|| hexValueBody.includes('__fallback_result')
	|| hexValueBody.includes('Obj.magic')) {
	fail('StringTools._hexValue still uses legacy result recovery instead of its checked return plan')
}

const stdioSource = fs.readFileSync('out/sys_io_Stdio.ml', 'utf8')
for (const functionName of ['ocamlstdioinput_readBytes__impl', 'ocamlstdiooutput_writeBytes__impl']) {
	const start = stdioSource.indexOf(`let ${functionName} =`)
	const end = stdioSource.indexOf('\nlet ', start + 1)
	const body = stdioSource.slice(start, end)
	if (start < 0
		|| end < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic __fallback_result')) {
		fail(`${functionName} still recovers its exact Int result through the legacy fallback`)
	}
}
const writeStringStart = stdioSource.indexOf('let ocamlstdiooutput_writeString__impl =')
const writeStringEnd = stdioSource.indexOf('\nlet ', writeStringStart + 1)
const writeStringBody = stdioSource.slice(writeStringStart, writeStringEnd)
if (writeStringStart < 0
	|| writeStringEnd < 0
	|| !writeStringBody.includes('raise (HxRuntime.Hx_return_void)')
	|| !writeStringBody.includes('| HxRuntime.Hx_return_void -> ()')
	|| writeStringBody.includes('Hx_return (Obj.repr ())')) {
	fail('ocamlstdiooutput_writeString__impl still packages its payloadless return as a value')
}

const returnControls = report.controls.filter(control => control.kind === 'return')
if (returnControls.length !== 56) {
	fail(`expected 56 represented return decisions, including eight nullable anonymous parse returns, StringTools._hexValue, the three stdio instance methods, and Exception.details, got ${returnControls.length}`)
}
const expectedByFunction = new Map([
	['branch', 1],
	['loop', 1],
	['nestedBlock', 1],
	['throughTry', 2],
	['boolBranch', 1],
	['stringThroughTry', 2],
	['nullableStringCarrier', 1],
	['dynamicBranch', 1],
	['nestedClosure', 1]
])
for (const [name, expectedCount] of expectedByFunction) {
	const decisions = returnControls.filter(control =>
		control.functionId.includes(`|function|${name}|`)
		&& !control.functionId.includes('|nested-function|'))
	if (decisions.length !== expectedCount) {
		fail(`expected ${expectedCount} sealed ${name} return decisions, got ${decisions.length}`)
	}
}
if (returnControls.some(control =>
	control.functionId.includes('|function|local|'))) {
	fail('the outer method control plan incorrectly claimed the nested function literal')
}
const nestedFunctionControls = returnControls.filter(control =>
	control.functionId.includes('|function|nestedClosure|')
	&& control.functionId.includes('|nested-function|'))
if (nestedFunctionControls.length !== 1) {
	fail(`expected one independently sealed nested-function return decision, got ${nestedFunctionControls.length}`)
}
const representedNestedFunctions = new Map([
	['nestedBoolClosure', 'Bool'],
	['nestedStringClosure', 'String'],
	['nestedNullableIntClosure', 'Null<Int>'],
	['nestedNullableBoolClosure', 'Null<Bool>'],
	['nestedDynamicClosure', 'Dynamic'],
	['nestedZeroArgumentClosure', 'Int'],
	['nestedArrayThrowClosure', 'Int'],
	['nestedArrayLiteralThrowClosure', 'Int'],
	['nestedStringArrayLiteralThrowClosure', 'Int'],
	['nestedNominalClosure', '_Main.NestedReturnBox']
])
for (const [functionName, semanticType] of representedNestedFunctions) {
	const decisions = returnControls.filter(control =>
		control.functionId.includes(`|function|${functionName}|`)
		&& control.functionId.includes('|nested-function|'))
	if (decisions.length !== 1 || decisions[0].payload.outputSemanticTypeId !== semanticType) {
		fail(`${functionName} did not seal one nested ${semanticType} return decision`)
	}
}
const deepNestedFunctionControls = returnControls.filter(control =>
	control.functionId.includes('|function|deepNestedClosure|')
	&& control.functionId.includes('|nested-function|'))
if (deepNestedFunctionControls.length !== 2
	|| !deepNestedFunctionControls.some(control =>
		control.functionId.split('|nested-function|').length - 1 === 2)) {
	fail('the two-level closure did not preserve an independently sealed child under its admitted nested parent')
}
for (const [functionName, expectedCount] of [['nestedCatchClosure', 2], ['nestedThrowCatchClosure', 1]]) {
	const decisions = returnControls.filter(control =>
		control.functionId.includes(`|function|${functionName}|`)
		&& control.functionId.includes('|nested-function|'))
	if (decisions.length !== expectedCount) {
		fail(`${functionName} did not seal its ${expectedCount} nested return decisions`)
	}
}

const nestedThrows = report.controls.filter(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedThrowCatchClosure|')
	&& control.functionId.includes('|nested-function|'))
if (nestedThrows.length !== 1
	|| nestedThrows[0].payload?.inputSemanticTypeId !== 'Int'
	|| nestedThrows[0].payload?.inputCarrierTypeId !== 'int'
	|| nestedThrows[0].payload?.conversion !== 'repr-and-recover-exact-value'
	|| nestedThrows[0].proofId !== 'exact-value-throw-control-v1'
	|| nestedThrows[0].pipelineRevision !== 'ocaml-nested-function-plans-v25') {
	fail('nestedThrowCatchClosure did not seal its exact Int throw under the nested binding')
}
const nestedArrayThrows = report.controls.filter(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedArrayThrowClosure|')
	&& control.functionId.includes('|nested-function|'))
if (nestedArrayThrows.length !== 1
	|| nestedArrayThrows[0].payload?.inputSemanticTypeId !== 'Array<Int>'
	|| nestedArrayThrows[0].payload?.inputCarrierTypeId !== 'int HxArray.t'
	|| nestedArrayThrows[0].payload?.inputRepresentationId !== 'representation:Array<Int>:internal-value'
	|| !sha256.test(nestedArrayThrows[0].payload?.representationRevision ?? '')
	|| nestedArrayThrows[0].payload?.arrayDescriptorId !== 'represented-array:Array<Int>'
	|| !sha256.test(nestedArrayThrows[0].payload?.arrayDescriptorRevision ?? '')
	|| nestedArrayThrows[0].payload?.conversion !== 'box-represented-array-throw-carrier'
	|| nestedArrayThrows[0].proofId !== 'represented-array-throw-control-v1'
	|| nestedArrayThrows[0].runtimeTags.join(',') !== 'Dynamic,Array') {
	fail('nestedArrayThrowClosure did not seal its exact Array<Int> throw and runtime tags')
}
const nestedArrayRepresentation = report.representations.find(decision =>
	decision.id === nestedArrayThrows[0].payload.inputRepresentationId)
const nestedArrayDescriptor = report.representedArrays.find(descriptor =>
	descriptor.id === nestedArrayThrows[0].payload.arrayDescriptorId)
if (nestedArrayRepresentation?.revision !== nestedArrayThrows[0].payload.representationRevision
	|| nestedArrayRepresentation?.arrayDescriptorId !== nestedArrayDescriptor?.id
	|| nestedArrayRepresentation?.arrayDescriptorRevision !== nestedArrayDescriptor?.revision
	|| nestedArrayDescriptor?.revision !== nestedArrayThrows[0].payload.arrayDescriptorRevision
	|| nestedArrayDescriptor?.elementSemanticTypeId !== 'Int'
	|| nestedArrayDescriptor?.elementRepresentationId !== 'representation:Int:array-element'
	|| !sha256.test(nestedArrayDescriptor?.elementRepresentationRevision ?? '')) {
	fail('nestedArrayThrowClosure did not bind the exact representation, array descriptor, and element revisions')
}
if (nestedArrayThrows[0].payload.arrayLiteralProducerId != null
	|| nestedArrayThrows[0].payload.arrayLiteralProducerPlanRevision != null) {
	fail('the local Array<Int> throw incorrectly claimed a direct-literal producer')
}

if (report.arrayLiteralProducerModel !== 'ocaml-represented-array-literal-producer-v3'
	|| report.arrayLiteralProducerCount !== report.arrayLiteralProducers.length
	|| report.arrayLiteralProducerCount !== 4
	|| !sha256.test(report.arrayLiteralProducerRevision)) {
	fail('unexpected direct represented-array literal producer model, inventory, or revision')
}
const literalProducers = report.arrayLiteralProducers.filter(producer =>
	producer.functionId.includes('|function|nestedArrayLiteralThrowClosure|')
	&& producer.functionId.includes('|nested-function|'))
if (literalProducers.length !== 1) {
	fail(`nestedArrayLiteralThrowClosure produced ${literalProducers.length} direct-literal plans instead of one`)
}
const literalProducer = literalProducers[0]
const expectedSchedule = [
	'create-array:-:-',
	'evaluate-element:0:0',
	'store-element:0:0',
	'evaluate-element:1:1',
	'store-element:1:1',
	'result-array:-:-'
]
const scheduleFor = producer => producer.evaluationSchedule.map(step => {
	const elementIndex = step.elementIndex == null ? '-' : String(step.elementIndex)
	const producerIndex = step.elementProducerId == null
		? '-'
		: String(producer.elements.findIndex(element => element.id === step.elementProducerId))
	return `${step.kind}:${elementIndex}:${producerIndex}`
})
function requireArrayLiteralRuntimeOwnership(producer) {
	const requirementId = `${producer.id}:runtime:haxe-array-literal-construction`
	const expectedSymbols = ['HxArray.create', ...producer.elements.map(() => 'HxArray.push')]
	const expectedRoles = ['create-array', ...producer.elements.map((_, index) => `store-element:${index}`)]
	const expectedOrders = [0, ...producer.elements.map((_, index) => index * 2 + 2)]
	if (producer.runtimeRequirementIds?.join(',') !== requirementId
		|| producer.runtimeUseOccurrences?.length !== expectedSymbols.length
		|| producer.runtimeUseOccurrences.some((use, index) =>
			use.id !== `${producer.id}:runtime-use:${index === 0 ? 'create' : `push:${index - 1}`}`
			|| !sha256.test(use.planRevision)
			|| use.ownerId !== producer.id
			|| use.requirementId !== requirementId
			|| use.domain !== 'expression-identifier'
			|| use.exactSymbol !== expectedSymbols[index]
			|| use.role !== expectedRoles[index]
			|| use.order !== expectedOrders[index]
			|| use.profileEligibility?.join(',') !== 'metal,portable'
			|| use.cardinality !== 1)) {
		fail(`direct ${producer.arraySemanticTypeId} literal does not own its exact HxArray.create/push occurrences`)
	}
	const requirement = report.runtimeRequirements.find(entry => entry.id === requirementId)
	if (requirement?.semanticCapability !== 'haxe-array-literal-construction'
		|| requirement.implementationFeature !== 'haxe-array-literal-construction-v1'
		|| requirement.sourceKind !== 'haxe-expression'
		|| requirement.sourceId !== producer.id
		|| requirement.decisionId !== producer.id
		|| requirement.subject?.id !== producer.arraySemanticTypeId
		|| requirement.rootModules?.join(',') !== 'HxArray'
		|| requirement.profileEligibility?.join(',') !== 'metal,portable') {
		fail(`direct ${producer.arraySemanticTypeId} literal does not publish its exact HxArray runtime requirement`)
	}
}
if (!literalProducer.id.startsWith('array-literal-producer:')
	|| literalProducer.literalOrdinal !== 0
	|| literalProducer.arraySemanticTypeId !== 'Array<Int>'
	|| literalProducer.arrayCarrierTypeId !== 'int HxArray.t'
	|| literalProducer.resultRepresentationId !== 'representation:Array<Int>:internal-value'
	|| !sha256.test(literalProducer.resultRepresentationRevision)
	|| literalProducer.arrayDescriptorId !== 'represented-array:Array<Int>'
	|| !sha256.test(literalProducer.arrayDescriptorRevision)
	|| literalProducer.elementSemanticTypeId !== 'Int'
	|| literalProducer.elementCarrierTypeId !== 'int'
	|| literalProducer.elementRepresentationId !== 'representation:Int:array-element'
	|| !sha256.test(literalProducer.elementRepresentationRevision)
	|| literalProducer.constructionPolicy !== 'create-then-evaluate-and-push-in-order'
	|| literalProducer.proofId !== 'direct-array-int-literal-construction-v1'
	|| literalProducer.profileEligibility.join(',') !== 'metal,portable'
	|| literalProducer.elements.length !== 2
	|| literalProducer.elements.some((element, index) =>
		element.index !== index
		|| element.semanticTypeId !== 'Int'
		|| element.carrierTypeId !== 'int'
		|| element.representationId !== literalProducer.elementRepresentationId
		|| element.representationRevision !== literalProducer.elementRepresentationRevision
		|| !element.source.file
		|| element.source.max < element.source.min)
	|| scheduleFor(literalProducer).join(',') !== expectedSchedule.join(',')) {
	fail('nestedArrayLiteralThrowClosure did not seal its exact ordered Array<Int> literal construction')
}
requireArrayLiteralRuntimeOwnership(literalProducer)
const literalThrows = report.controls.filter(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedArrayLiteralThrowClosure|')
	&& control.functionId.includes('|nested-function|'))
if (literalThrows.length !== 1
	|| literalThrows[0].payload?.arrayLiteralProducerId !== literalProducer.id
	|| !sha256.test(literalThrows[0].payload?.arrayLiteralProducerPlanRevision ?? '')
	|| literalThrows[0].functionId !== literalProducer.functionId
	|| literalThrows[0].programRevision !== literalProducer.programRevision
	|| literalThrows[0].bodyRevision !== literalProducer.bodyRevision
	|| literalThrows[0].pipelineRevision !== literalProducer.pipelineRevision
	|| literalThrows[0].payload.inputRepresentationId !== literalProducer.resultRepresentationId
	|| literalThrows[0].payload.representationRevision !== literalProducer.resultRepresentationRevision
	|| literalThrows[0].payload.arrayDescriptorId !== literalProducer.arrayDescriptorId
	|| literalThrows[0].payload.arrayDescriptorRevision !== literalProducer.arrayDescriptorRevision
	|| !literalThrows[0].proofClaim.includes(literalProducer.id)) {
	fail('the direct Array<Int> literal throw did not consume its exact producer and representation graph')
}
const stringLiteralProducers = report.arrayLiteralProducers.filter(producer =>
	producer.functionId.includes('|function|nestedStringArrayLiteralThrowClosure|')
	&& producer.functionId.includes('|nested-function|'))
if (stringLiteralProducers.length !== 1) {
	fail(`nestedStringArrayLiteralThrowClosure produced ${stringLiteralProducers.length} direct-literal plans instead of one`)
}
const stringLiteralProducer = stringLiteralProducers[0]
if (!stringLiteralProducer.id.startsWith('array-literal-producer:')
	|| stringLiteralProducer.literalOrdinal !== 0
	|| stringLiteralProducer.arraySemanticTypeId !== 'Array<String>'
	|| stringLiteralProducer.arrayCarrierTypeId !== 'string HxArray.t'
	|| stringLiteralProducer.resultRepresentationId !== 'representation:Array<String>:internal-value'
	|| !sha256.test(stringLiteralProducer.resultRepresentationRevision)
	|| stringLiteralProducer.arrayDescriptorId !== 'represented-array:Array<String>'
	|| !sha256.test(stringLiteralProducer.arrayDescriptorRevision)
	|| stringLiteralProducer.elementSemanticTypeId !== 'String'
	|| stringLiteralProducer.elementCarrierTypeId !== 'string'
	|| stringLiteralProducer.elementRepresentationId !== 'representation:String:array-element'
	|| !sha256.test(stringLiteralProducer.elementRepresentationRevision)
	|| stringLiteralProducer.constructionPolicy !== 'create-then-evaluate-and-push-in-order'
	|| stringLiteralProducer.proofId !== 'direct-array-string-literal-construction-v1'
	|| stringLiteralProducer.profileEligibility.join(',') !== 'metal,portable'
	|| stringLiteralProducer.elements.length !== 2
	|| stringLiteralProducer.elements.some((element, index) =>
		element.index !== index
		|| element.semanticTypeId !== 'String'
		|| element.carrierTypeId !== 'string'
		|| element.representationId !== stringLiteralProducer.elementRepresentationId
		|| element.representationRevision !== stringLiteralProducer.elementRepresentationRevision
		|| !element.source.file
		|| element.source.max < element.source.min)
	|| scheduleFor(stringLiteralProducer).join(',') !== expectedSchedule.join(',')) {
	fail('nestedStringArrayLiteralThrowClosure did not seal its exact ordered Array<String> literal construction')
}
requireArrayLiteralRuntimeOwnership(stringLiteralProducer)
const stringLiteralThrows = report.controls.filter(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedStringArrayLiteralThrowClosure|')
	&& control.functionId.includes('|nested-function|'))
if (stringLiteralThrows.length !== 1
	|| stringLiteralThrows[0].payload?.arrayLiteralProducerId !== stringLiteralProducer.id
	|| !sha256.test(stringLiteralThrows[0].payload?.arrayLiteralProducerPlanRevision ?? '')
	|| stringLiteralThrows[0].functionId !== stringLiteralProducer.functionId
	|| stringLiteralThrows[0].programRevision !== stringLiteralProducer.programRevision
	|| stringLiteralThrows[0].bodyRevision !== stringLiteralProducer.bodyRevision
	|| stringLiteralThrows[0].pipelineRevision !== stringLiteralProducer.pipelineRevision
	|| stringLiteralThrows[0].payload.inputSemanticTypeId !== 'Array<String>'
	|| stringLiteralThrows[0].payload.inputCarrierTypeId !== 'string HxArray.t'
	|| stringLiteralThrows[0].payload.inputRepresentationId !== stringLiteralProducer.resultRepresentationId
	|| stringLiteralThrows[0].payload.representationRevision !== stringLiteralProducer.resultRepresentationRevision
	|| stringLiteralThrows[0].payload.arrayDescriptorId !== stringLiteralProducer.arrayDescriptorId
	|| stringLiteralThrows[0].payload.arrayDescriptorRevision !== stringLiteralProducer.arrayDescriptorRevision
	|| stringLiteralThrows[0].payload.conversion !== 'box-represented-array-throw-carrier'
	|| stringLiteralThrows[0].runtimeTags.join(',') !== 'Dynamic,Array'
	|| !stringLiteralThrows[0].proofClaim.includes(stringLiteralProducer.id)) {
	fail('the direct Array<String> literal throw did not consume its exact producer and representation graph')
}
const nestedCatches = report.controlCatches.filter(catchChain =>
	catchChain.functionId.includes('|nested-function|')
	&& (catchChain.functionId.includes('|function|nestedCatchClosure|')
		|| catchChain.functionId.includes('|function|nestedThrowCatchClosure|')))
if (nestedCatches.length !== 2
	|| nestedCatches.some(catchChain =>
		catchChain.pipelineRevision !== 'ocaml-nested-function-plans-v25'
		|| catchChain.privateControlPolicy !== 'propagate-private-control-signals'
		|| catchChain.clauses.length !== 1)) {
	fail('the two nested catch chains are missing or do not preserve private control signals')
}
const intCatch = nestedCatches.find(catchChain => catchChain.functionId.includes('|function|nestedThrowCatchClosure|'))
if (intCatch?.clauses[0].semanticTypeId !== 'Int'
	|| intCatch.clauses[0].outputCarrierTypeId !== 'int'
	|| intCatch.clauses[0].matchPolicy !== 'exact-runtime-tag'
	|| intCatch.clauses[0].runtimeTag !== 'Int') {
	fail('nestedThrowCatchClosure did not seal the exact Int catch policy')
}

const nestedLoopTargets = report.controlTargets.filter(target =>
	target.functionId.includes('|function|nestedLoopClosure|')
	&& target.functionId.includes('|nested-function|'))
const nestedLoopTransfers = report.controls.filter(control =>
	(control.kind === 'break' || control.kind === 'continue')
	&& control.functionId.includes('|function|nestedLoopClosure|')
	&& control.functionId.includes('|nested-function|'))
const nestedLoopReturns = returnControls.filter(control =>
	control.functionId.includes('|function|nestedLoopClosure|')
	&& control.functionId.includes('|nested-function|'))
if (nestedLoopTargets.length !== 1
	|| nestedLoopTransfers.length !== 2
	|| nestedLoopReturns.length !== 1
	|| nestedLoopTransfers.filter(control => control.kind === 'break').length !== 1
	|| nestedLoopTransfers.filter(control => control.kind === 'continue').length !== 1
	|| nestedLoopTargets[0].pipelineRevision !== 'ocaml-nested-function-plans-v25'
	|| nestedLoopReturns[0].functionId !== nestedLoopTargets[0].functionId
	|| nestedLoopReturns[0].pipelineRevision !== nestedLoopTargets[0].pipelineRevision
	|| nestedLoopReturns[0].bodyRevision !== nestedLoopTargets[0].bodyRevision
	|| nestedLoopReturns[0].programRevision !== nestedLoopTargets[0].programRevision
	|| nestedLoopTransfers.some(control =>
		control.functionId !== nestedLoopTargets[0].functionId
		|| control.targetId !== nestedLoopTargets[0].id
		|| control.pipelineRevision !== nestedLoopTargets[0].pipelineRevision
		|| control.bodyRevision !== nestedLoopTargets[0].bodyRevision
		|| control.programRevision !== nestedLoopTargets[0].programRevision)) {
	fail('nestedLoopClosure did not seal one exact lexical loop with its break, continue, and return decisions')
}

const ids = new Set()
for (const control of returnControls) {
	const effectOnlyVoid = control.proofId === 'effect-only-void-early-return-control-v1'
	if (effectOnlyVoid) {
		if (ids.has(control.id)
			|| control.kind !== 'return'
			|| control.effect !== 'exit-function'
			|| control.targetKind !== 'function'
			|| control.targetId !== control.functionId
			|| control.mechanism !== 'runtime-void-return-signal'
			|| control.runtimeCapabilityId !== 'hxhx-runtime:function-void-return-signal-v1'
			|| control.payload != null
			|| control.runtimeTags.length !== 0
			|| control.runtimeTagPolicy !== 'no-runtime-tags'
			|| control.profileEligibility.join(',') !== 'metal,portable'
			|| !control.reason
			|| !control.proofClaim
			|| !control.source.file
			|| control.source.min < 0
			|| control.source.max < control.source.min
			|| !rawSha256.test(control.programRevision)
			|| !bodyRevision.test(control.bodyRevision)
			|| control.pipelineRevision !== 'ocaml-function-plans-v104') {
			fail(`payloadless control decision ${control.id} has incomplete identity, target, proof, profile, source, or revision`)
		}
		ids.add(control.id)
		continue
	}
	if (ids.has(control.id)
		|| control.kind !== 'return'
		|| control.effect !== 'exit-function'
		|| control.targetKind !== 'function'
		|| control.targetId !== control.functionId
		|| control.mechanism !== 'runtime-return-signal'
		|| control.runtimeCapabilityId !== 'hxhx-runtime:function-return-signal-v1'
		|| control.runtimeTags.length !== 0
		|| control.runtimeTagPolicy !== 'no-runtime-tags'
		|| control.profileEligibility.join(',') !== 'metal,portable'
		|| !control.reason
		|| !control.proofClaim
		|| !control.source.file
		|| control.source.min < 0
		|| control.source.max < control.source.min
		|| !rawSha256.test(control.programRevision)
		|| !bodyRevision.test(control.bodyRevision)
		|| (control.functionId.includes('|nested-function|')
			? control.pipelineRevision !== 'ocaml-nested-function-plans-v25'
			: control.pipelineRevision !== 'ocaml-function-plans-v104')) {
		fail(`control decision ${control.id} has incomplete identity, target, proof, profile, source, or revision`)
	}
	const payload = control.payload
	const exactCarrier = new Map([
		['Int', 'int'],
		['Bool', 'bool'],
		['String', 'string']
	]).get(payload.inputSemanticTypeId)
	const exactValue = exactCarrier != null
		&& control.proofId === 'exact-value-early-return-control-v2'
		&& payload.inputCarrierTypeId === exactCarrier
		&& payload.inputRepresentationId === `representation:${payload.inputSemanticTypeId}:internal-value`
		&& payload.outputSemanticTypeId === payload.inputSemanticTypeId
		&& payload.outputCarrierTypeId === exactCarrier
		&& payload.outputRepresentationId === payload.inputRepresentationId
		&& payload.conversion === 'box-and-recover-exact-value'
		&& payload.proofId === 'exact-value-early-return-control-v2'
	const nullableInt = control.proofId === 'exact-int-to-nullable-early-return-control-v1'
		&& payload.inputSemanticTypeId === 'Int'
		&& payload.inputCarrierTypeId === 'int'
		&& payload.inputRepresentationId === 'representation:Int:internal-value'
		&& payload.outputSemanticTypeId === 'Null<Int>'
		&& payload.outputCarrierTypeId === 'Obj.t'
		&& payload.outputRepresentationId === 'representation:Null<Int>:internal-value'
		&& payload.conversion === 'box-exact-int-to-nullable-carrier'
		&& payload.proofId === 'exact-int-to-nullable-early-return-control-v1'
	const nullableBool = control.proofId === 'exact-bool-to-nullable-early-return-control-v1'
		&& payload.inputSemanticTypeId === 'Bool'
		&& payload.inputCarrierTypeId === 'bool'
		&& payload.inputRepresentationId === 'representation:Bool:internal-value'
		&& payload.outputSemanticTypeId === 'Null<Bool>'
		&& payload.outputCarrierTypeId === 'Obj.t'
		&& payload.outputRepresentationId === 'representation:Null<Bool>:internal-value'
		&& payload.conversion === 'box-exact-bool-to-nullable-carrier'
		&& payload.proofId === 'exact-bool-to-nullable-early-return-control-v1'
	const dynamicCarrier = control.proofId === 'dynamic-carrier-return-control-v1'
		&& payload.inputSemanticTypeId === 'Dynamic'
		&& payload.inputCarrierTypeId === 'Obj.t'
		&& payload.inputRepresentationId === 'representation:Dynamic:internal-value'
		&& payload.outputSemanticTypeId === 'Dynamic'
		&& payload.outputCarrierTypeId === 'Obj.t'
		&& payload.outputRepresentationId === payload.inputRepresentationId
		&& payload.conversion === 'preserve-dynamic-return-carrier'
		&& payload.proofId === 'dynamic-carrier-return-control-v1'
	const anonymousCarrier = control.proofId === 'exact-anonymous-carrier-early-return-control-v1'
		&& payload.inputSemanticTypeId === 'anonymous{file:String,line:Int}'
		&& payload.inputCarrierTypeId === 'Obj.t'
		&& payload.inputRepresentationId === 'representation:anonymous{file:String,line:Int}:internal-value'
		&& payload.outputSemanticTypeId === payload.inputSemanticTypeId
		&& payload.outputCarrierTypeId === 'Obj.t'
		&& payload.outputRepresentationId === payload.inputRepresentationId
		&& /^sha256:[0-9a-f]{64}$/.test(payload.representationRevision ?? '')
		&& payload.conversion === 'preserve-anonymous-carrier'
		&& payload.nominalRepresentation == null
		&& payload.proofId === 'exact-anonymous-carrier-early-return-control-v1'
	const nominal = payload.nominalRepresentation
	const nominalValue = control.proofId === 'exact-monomorphic-class-early-return-control-v1'
		&& payload.inputSemanticTypeId === '_Main.NestedReturnBox'
		&& payload.inputCarrierTypeId === 'nestedreturnbox_t'
		&& payload.inputRepresentationId === 'representation:_Main.NestedReturnBox:internal-value'
		&& payload.outputSemanticTypeId === payload.inputSemanticTypeId
		&& payload.outputCarrierTypeId === payload.inputCarrierTypeId
		&& payload.outputRepresentationId === payload.inputRepresentationId
		&& payload.conversion === 'box-and-recover-nominal-value'
		&& payload.proofId === 'exact-monomorphic-class-early-return-control-v1'
		&& nominal?.targetModuleName === 'Main'
		&& nominal?.targetTypeName === 'nestedreturnbox_t'
		&& /^sha256:[0-9a-f]{64}$/.test(nominal?.layoutRevision ?? '')
		&& nominal?.representationProofId === `whole-program-monomorphic-nominal-record-v1:${nominal.layoutRevision}`
	if (payload.signalCarrierTypeId !== 'Obj.t'
		|| (!exactValue && !nullableInt && !nullableBool && !dynamicCarrier && !anonymousCarrier && !nominalValue)
		|| !payload.proofClaim) {
		fail(`control decision ${control.id} has an incomplete represented return payload crossing`)
	}
	ids.add(control.id)
}

for (const name of ['branch', 'loop', 'nestedBlock', 'throughTry', 'boolBranch', 'stringThroughTry', 'nullableStringCarrier']) {
	const start = source.indexOf(`let ${name} =`)
	const next = source.indexOf('\nlet ', start + 1)
	if (start < 0 || next < 0) {
		fail(`generated source is missing function ${name}`)
	}
	const body = source.slice(start, next)
	if (!body.includes('HxRuntime.Hx_return')
		|| !body.includes('Obj.repr')
		|| !body.includes('Obj.obj')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic')) {
		fail(`${name} did not hard-cut to the sealed exact-value return mechanism`)
	}
}
const tryStart = source.indexOf('let throughTry =')
const tryEnd = source.indexOf('\nlet nestedClosure =', tryStart)
const tryBody = source.slice(tryStart, tryEnd)
if (!/HxRuntime\.Hx_return __ret_\d+ -> raise \(HxRuntime\.Hx_return __ret_\d+\)/.test(tryBody)) {
	fail('a source catch can intercept the private function-return signal')
}
const stringTryStart = source.indexOf('let stringThroughTry =')
const stringTryEnd = source.indexOf('\nlet nestedClosure =', stringTryStart)
const stringTryBody = source.slice(stringTryStart, stringTryEnd)
if (!/HxRuntime\.Hx_return __ret_\d+ -> raise \(HxRuntime\.Hx_return __ret_\d+\)/.test(stringTryBody)
	|| !/Obj\.obj __ret_\d+ : string/.test(stringTryBody)) {
	fail('the exact-String try boundary does not rethrow private control before recovering its sealed string carrier')
}
const boolStart = source.indexOf('let boolBranch =')
const boolEnd = source.indexOf('\nlet stringThroughTry =', boolStart)
const boolBody = source.slice(boolStart, boolEnd)
if (!/Obj\.obj __ret_\d+ : bool/.test(boolBody)) {
	fail('the exact-Bool boundary did not recover its sealed bool carrier')
}
const nullableStringStart = source.indexOf('let nullableStringCarrier =')
const nullableStringEnd = source.indexOf('\nlet nestedClosure =', nullableStringStart)
const nullableStringBody = source.slice(nullableStringStart, nullableStringEnd)
const boxesNullString = nullableStringBody.includes('Obj.repr HxString.hx_null_string')
	|| nullableStringBody.includes('Obj.repr (HxString.hx_null_string)')
if (!boxesNullString
	|| !/Obj\.obj __ret_\d+ : string/.test(nullableStringBody)) {
	fail('the exact-String boundary did not preserve the existing runtime null-sentinel carrier')
}
const closureStart = source.indexOf('let nestedClosure =')
const closureEnd = source.indexOf('\nlet nestedBoolClosure =', closureStart)
const closureBody = source.slice(closureStart, closureEnd)
if (!closureBody.includes('let local = fun')
	|| !closureBody.includes('HxRuntime.Hx_return')
	|| !closureBody.includes('Obj.repr')
	|| !closureBody.includes('Obj.obj')
	|| closureBody.includes('__fallback_result')
	|| closureBody.includes('Obj.magic')
	|| !closureBody.includes(': int)')) {
	fail('the nested function literal did not consume its independent exact-Int return plan')
}
for (const [functionName, expectedType] of [
	['nestedBoolClosure', 'bool'],
	['nestedStringClosure', 'string'],
	['nestedNullableIntClosure', 'Obj.t'],
	['nestedNullableBoolClosure', 'Obj.t'],
	['nestedDynamicClosure', 'Obj.t'],
	['nestedZeroArgumentClosure', 'int']
]) {
	const start = source.indexOf(`let ${functionName} =`)
	const next = source.indexOf('\nlet ', start + 1)
	const body = source.slice(start, next)
	if (start < 0
		|| next < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic')
		|| (functionName === 'nestedZeroArgumentClosure' && !body.includes('let local = fun () ->'))
		|| !body.includes(`: ${expectedType}`)) {
		fail(`${functionName} did not consume its represented nested return plan`)
	}
}
const dynamicClosureStart = source.indexOf('let nestedDynamicClosure =')
const dynamicClosureEnd = source.indexOf('\nlet nestedZeroArgumentClosure =', dynamicClosureStart)
const dynamicClosureBody = source.slice(dynamicClosureStart, dynamicClosureEnd)
if (dynamicClosureStart < 0
	|| dynamicClosureEnd < 0
	|| !dynamicClosureBody.includes('HxRuntime.Hx_return early')
	|| !/HxRuntime\.Hx_return __ret_\d+ -> \(__ret_\d+ : Obj\.t\)/.test(dynamicClosureBody)
	|| dynamicClosureBody.includes('HxRuntime.Hx_return (Obj.repr')
	|| dynamicClosureBody.includes('Obj.obj')
	|| dynamicClosureBody.includes('Obj.magic')
	|| dynamicClosureBody.includes('__fallback_result')) {
	fail('nestedDynamicClosure did not preserve its existing Dynamic Obj.t carrier through the private return signal')
}
const dynamicBranchControl = returnControls.find(control =>
	control.functionId.includes('|function|dynamicBranch|')
	&& !control.functionId.includes('|nested-function|'))
const dynamicBranchStart = source.indexOf('let dynamicBranch =')
const dynamicBranchEnd = source.indexOf('\nlet ', dynamicBranchStart + 1)
const dynamicBranchBody = source.slice(dynamicBranchStart, dynamicBranchEnd)
if (dynamicBranchControl?.pipelineRevision !== 'ocaml-function-plans-v104'
	|| dynamicBranchControl.proofId !== 'dynamic-carrier-return-control-v1'
	|| dynamicBranchStart < 0
	|| dynamicBranchEnd < 0
	|| !dynamicBranchBody.includes('HxRuntime.Hx_return early')
	|| !/HxRuntime\.Hx_return __ret_\d+ -> \(__ret_\d+ : Obj\.t\)/.test(dynamicBranchBody)
	|| dynamicBranchBody.includes('HxRuntime.Hx_return (Obj.repr')
	|| dynamicBranchBody.includes('Obj.obj')
	|| dynamicBranchBody.includes('Obj.magic')
	|| dynamicBranchBody.includes('__fallback_result')) {
	fail('dynamicBranch did not preserve its existing Dynamic Obj.t carrier through the current root return plan')
}
const arrayThrowStart = source.indexOf('let nestedArrayThrowClosure =')
const arrayThrowEnd = source.indexOf('\nlet nestedStringArrayLiteralThrowClosure =', arrayThrowStart)
const arrayThrowBody = source.slice(arrayThrowStart, arrayThrowEnd)
const arrayLocalStart = arrayThrowBody.indexOf('let local = fun')
const arrayLocalEnd = arrayThrowBody.indexOf(' in let result =', arrayLocalStart)
const arrayLocalBody = arrayThrowBody.slice(arrayLocalStart, arrayLocalEnd)
if (arrayThrowStart < 0
	|| arrayThrowEnd < 0
	|| arrayLocalStart < 0
	|| arrayLocalEnd < 0
	|| !arrayLocalBody.includes('HxRuntime.Hx_return')
	|| !arrayLocalBody.includes('HxType.hx_throw_typed_rtti (Obj.repr expected) ["Dynamic"; "Array"]')
	|| !/HxRuntime\.Hx_return __ret_\d+ -> \(Obj\.obj __ret_\d+ : int\)/.test(arrayLocalBody)
	|| arrayLocalBody.includes('__fallback_result')
	|| arrayLocalBody.includes('Obj.magic')) {
	fail('nestedArrayThrowClosure did not consume its exact Array<Int> throw and return plans')
}
const literalThrowStart = source.indexOf('let nestedArrayLiteralThrowClosure =')
const literalThrowEnd = source.indexOf('\nlet nestedStringArrayLiteralThrowClosure =', literalThrowStart)
const literalThrowBody = source.slice(literalThrowStart, literalThrowEnd)
const literalLocalStart = literalThrowBody.indexOf('let local = fun')
const literalLocalEnd = literalThrowBody.indexOf(' : int) in (', literalLocalStart)
const literalLocalBody = literalThrowBody.slice(literalLocalStart, literalLocalEnd)
const createIndex = literalLocalBody.indexOf('HxArray.create ()')
const firstElementIndex = literalLocalBody.indexOf('arrayLiteralThrowElement')
const secondElementIndex = literalLocalBody.indexOf('arrayLiteralThrowElement', firstElementIndex + 1)
if (literalThrowStart < 0
	|| literalThrowEnd < 0
	|| literalLocalStart < 0
	|| literalLocalEnd < 0
	|| (literalLocalBody.match(/HxArray\.create \(\)/g) ?? []).length !== 1
	|| (literalLocalBody.match(/arrayLiteralThrowElement/g) ?? []).length !== 2
	|| (literalLocalBody.match(/HxArray\.push/g) ?? []).length !== 2
	|| createIndex < 0
	|| firstElementIndex <= createIndex
	|| secondElementIndex <= firstElementIndex
	|| !literalLocalBody.includes('HxType.hx_throw_typed_rtti')
	|| !literalLocalBody.includes('["Dynamic"; "Array"]')
	|| !literalLocalBody.includes('HxRuntime.Hx_return (Obj.repr 59)')
	|| literalLocalBody.includes('__fallback_result')
	|| literalLocalBody.includes('Obj.magic')) {
	fail('nestedArrayLiteralThrowClosure did not consume one ordered direct-literal producer before its exact throw plan')
}
const stringLiteralThrowStart = source.indexOf('let nestedStringArrayLiteralThrowClosure =')
const stringLiteralThrowEnd = source.indexOf('\nlet nestedNominalClosure =', stringLiteralThrowStart)
const stringLiteralThrowBody = source.slice(stringLiteralThrowStart, stringLiteralThrowEnd)
const stringLiteralLocalStart = stringLiteralThrowBody.indexOf('let local = fun')
const stringLiteralLocalEnd = stringLiteralThrowBody.indexOf(' : int) in let ordinaryResult', stringLiteralLocalStart)
const stringLiteralLocalBody = stringLiteralThrowBody.slice(stringLiteralLocalStart, stringLiteralLocalEnd)
const stringCreateIndex = stringLiteralLocalBody.indexOf('HxArray.create ()')
const firstStringElementIndex = stringLiteralLocalBody.indexOf('stringArrayLiteralThrowElement')
const secondStringElementIndex = stringLiteralLocalBody.indexOf('stringArrayLiteralThrowElement', firstStringElementIndex + 1)
if (stringLiteralThrowStart < 0
	|| stringLiteralThrowEnd < 0
	|| stringLiteralLocalStart < 0
	|| stringLiteralLocalEnd < 0
	|| (stringLiteralLocalBody.match(/HxArray\.create \(\)/g) ?? []).length !== 1
	|| (stringLiteralLocalBody.match(/stringArrayLiteralThrowElement/g) ?? []).length !== 2
	|| (stringLiteralLocalBody.match(/HxArray\.push/g) ?? []).length !== 2
	|| stringCreateIndex < 0
	|| firstStringElementIndex <= stringCreateIndex
	|| secondStringElementIndex <= firstStringElementIndex
	|| !stringLiteralLocalBody.includes('HxType.hx_throw_typed_rtti')
	|| !stringLiteralLocalBody.includes('["Dynamic"; "Array"]')
	|| !stringLiteralLocalBody.includes('HxRuntime.Hx_return (Obj.repr 49)')
	|| !/HxRuntime\.Hx_return __ret_\d+ -> \(Obj\.obj __ret_\d+ : int\)/.test(stringLiteralLocalBody)
	|| stringLiteralLocalBody.includes('__fallback_result')
	|| stringLiteralLocalBody.includes('Obj.magic')
	|| stringLiteralThrowBody.includes('__fallback_result')) {
	fail('nestedStringArrayLiteralThrowClosure did not consume one ordered direct String-literal producer before its exact throw and return plans')
}
const nominalClosureStart = source.indexOf('let nestedNominalClosure =')
const nominalClosureEnd = source.indexOf('\nlet deepNestedClosure =', nominalClosureStart)
const nominalClosureBody = source.slice(nominalClosureStart, nominalClosureEnd)
if (nominalClosureStart < 0
	|| nominalClosureEnd < 0
	|| !nominalClosureBody.includes('HxRuntime.Hx_return (Obj.repr expected)')
	|| !/HxRuntime\.Hx_return __ret_\d+ -> \(Obj\.obj __ret_\d+ : nestedreturnbox_t\)/.test(nominalClosureBody)
	|| nominalClosureBody.includes('__fallback_result')
	|| nominalClosureBody.includes('Obj.magic')) {
	fail('nestedNominalClosure did not preserve its sealed class record through the private return signal')
}
const deepClosureStart = source.indexOf('let deepNestedClosure =')
const deepClosureEnd = source.indexOf('\nlet nestedCatchClosure =', deepClosureStart)
const deepClosureBody = source.slice(deepClosureStart, deepClosureEnd)
if ((deepClosureBody.match(/HxRuntime\.Hx_return/g) ?? []).length < 4
	|| !deepClosureBody.includes('Obj.repr')
	|| !deepClosureBody.includes('Obj.obj')
	|| deepClosureBody.includes('__fallback_result')
	|| deepClosureBody.includes('Obj.magic')) {
	fail('the two-level nested functions did not consume their separate exact-Int return plans')
}
for (const functionName of ['nestedCatchClosure', 'nestedThrowCatchClosure']) {
	const start = source.indexOf(`let ${functionName} =`)
	const next = source.indexOf('\nlet ', start + 1)
	const body = source.slice(start, next)
	if (start < 0
		|| next < 0
		|| !body.includes('HxRuntime.Hx_return')
		|| !body.includes('HxRuntime.Hx_exception')
		|| !body.includes('raise (HxRuntime.Hx_return')
		|| body.includes('__fallback_result')
		|| body.includes('Obj.magic')) {
		fail(`${functionName} did not consume its nested return and catch plan without legacy result recovery`)
	}
}
const throwCatchStart = source.indexOf('let nestedThrowCatchClosure =')
const throwCatchEnd = source.indexOf('\nlet nestedLoopClosure =', throwCatchStart)
const throwCatchBody = source.slice(throwCatchStart, throwCatchEnd)
if (!throwCatchBody.includes('HxType.hx_throw_typed_rtti (Obj.repr 21) ["Dynamic"]')
	|| !throwCatchBody.includes('HxRuntime.tags_has __exn_tags_')
	|| !throwCatchBody.includes('"Int"')) {
	fail('nestedThrowCatchClosure did not consume the planned exact Int throw and catch tags')
}
const loopClosureStart = source.indexOf('let nestedLoopClosure =')
const loopClosureEnd = source.indexOf('\nlet main =', loopClosureStart)
const loopClosureBody = source.slice(loopClosureStart, loopClosureEnd)
if (!loopClosureBody.includes('raise (HxRuntime.Hx_break)')
	|| !loopClosureBody.includes('| HxRuntime.Hx_break -> ()')
	|| !loopClosureBody.includes('raise (HxRuntime.Hx_continue)')
	|| !loopClosureBody.includes('| HxRuntime.Hx_continue -> ()')
	|| !loopClosureBody.includes('HxRuntime.Hx_return')
	|| loopClosureBody.includes('__fallback_result')
	|| loopClosureBody.includes('Obj.magic')) {
	fail('nestedLoopClosure did not consume its exact nested loop and return plan')
}
NODE

cp "$REPORT_FILE" "$REPORT_COPY"
haxe build.hxml
if ! cmp -s "$REPORT_COPY" "$REPORT_FILE"; then
	echo "The exact same typed program produced a different lowering report" >&2
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
	|| report.summary.controlCount !== report.lowering.controls.length
	|| report.summary.controlTargetCount !== report.lowering.controlTargets.length
	|| report.summary.controlAdmissionCount !== report.lowering.controlAdmissions.length
	|| report.summary.controlAdmissionCount === 0
	|| report.summary.functionResultBoundaryCount !== report.lowering.functionResultBoundaries.length
	|| report.summary.functionResultBoundaryCount === 0
	|| report.summary.arrayLiteralProducerCount !== report.lowering.arrayLiteralProducers.length
	|| report.summary.arrayLiteralProducerCount !== 4
	|| report.lowering.controls.filter(control => control.kind === 'return').length !== 56
	|| report.lowering.scope !== 'typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families') {
	throw new Error('public inspection did not expose the 56 returns, their function-result owners, and four direct represented-array literal producers')
}
const hexValueResult = report.lowering.functionResultBoundaries.find(boundary =>
	boundary.functionId.includes('StringTools|StringTools|static|function|_hexValue|'))
const declarationOnlyResults = report.lowering.functionResultBoundaries.filter(boundary =>
	boundary.source === 'static-inline-exact-int-declaration')
if (!/^sha256:[0-9a-f]{64}$/.test(report.lowering.functionResultBoundaryRevision ?? '')
	|| hexValueResult?.source !== 'static-inline-exact-int-declaration'
	|| hexValueResult.callableBoundaryId != null
	|| hexValueResult.result?.inputSemanticTypeId !== 'Int'
	|| hexValueResult.result?.inputCarrierTypeId !== 'int'
	|| hexValueResult.result?.outputRepresentationId !== 'representation:Int:internal-value'
	|| hexValueResult.proofId !== 'static-inline-exact-int-function-result-v1'
	|| declarationOnlyResults.length !== 1
	|| declarationOnlyResults[0]?.id !== hexValueResult.id
	|| report.lowering.callableBoundaries.some(boundary => boundary.functionId === hexValueResult.functionId)) {
	throw new Error('public inspection did not preserve result-only ownership for StringTools._hexValue')
}
const instanceExactIntResults = report.lowering.functionResultBoundaries.filter(boundary =>
	boundary.source === 'non-generic-instance-exact-int-declaration')
if (instanceExactIntResults.length !== 2
	|| !instanceExactIntResults.some(boundary =>
		boundary.functionId.includes('sys.io.Stdio|OcamlStdioInput|instance|function|readBytes|'))
	|| !instanceExactIntResults.some(boundary =>
		boundary.functionId.includes('sys.io.Stdio|OcamlStdioOutput|instance|function|writeBytes|'))
	|| instanceExactIntResults.some(boundary =>
		boundary.callableBoundaryId != null
		|| boundary.result?.inputSemanticTypeId !== 'Int'
		|| boundary.result?.inputCarrierTypeId !== 'int'
		|| boundary.result?.outputRepresentationId !== 'representation:Int:internal-value'
		|| boundary.proofId !== 'non-generic-instance-exact-int-function-result-v1'
		|| report.lowering.callableBoundaries.some(callable => callable.functionId === boundary.functionId))) {
	throw new Error('public inspection did not preserve result-only ownership for the two stdio instance methods')
}
const instanceVoidResults = report.lowering.functionResultBoundaries.filter(boundary =>
	boundary.source === 'non-generic-instance-effect-only-void-declaration')
if (instanceVoidResults.length !== 1
	|| !instanceVoidResults[0].functionId.includes('sys.io.Stdio|OcamlStdioOutput|instance|function|writeString|')
	|| instanceVoidResults[0].callableBoundaryId != null
	|| instanceVoidResults[0].resultKind !== 'effect-only-void'
	|| instanceVoidResults[0].result != null
	|| instanceVoidResults[0].proofId !== 'non-generic-instance-effect-only-void-function-result-v1'
	|| report.lowering.callableBoundaries.some(callable => callable.functionId === instanceVoidResults[0].functionId)) {
	throw new Error('public inspection did not preserve result-only ownership for the stdio Void instance method')
}
const admittedParseAdmission = report.lowering.controlAdmissions.find(admission =>
	admission.functionId.includes('haxe.NativeStackTrace|NativeStackTrace|static|function|parseFileLine|'))
const admittedParseReturn = admittedParseAdmission?.families.find(family => family.family === 'return')
const admittedParseResult = report.lowering.functionResultBoundaries.find(boundary =>
	boundary.functionId === admittedParseAdmission?.functionId)
if (admittedParseReturn?.status !== 'admitted'
	|| admittedParseReturn.occurrenceCount !== 4
	|| admittedParseReturn.decisionCount !== 4
	|| admittedParseResult?.source !== 'static-nullable-anonymous-declaration'
	|| admittedParseResult.anonymousStructure?.semanticTypeId !== 'anonymous{file:String,line:Int}'
	|| !/^sha256:[0-9a-f]{64}$/.test(admittedParseAdmission.revision ?? '')) {
	throw new Error('public inspection did not validate the nullable anonymous parse result and its four return decisions')
}
const arrayThrow = report.lowering.controls.find(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedArrayThrowClosure|')
	&& control.functionId.includes('|nested-function|'))
if (arrayThrow?.payload?.inputSemanticTypeId !== 'Array<Int>'
	|| arrayThrow.payload.inputCarrierTypeId !== 'int HxArray.t'
	|| arrayThrow.payload.inputRepresentationId !== 'representation:Array<Int>:internal-value'
	|| !/^sha256:[0-9a-f]{64}$/.test(arrayThrow.payload.representationRevision ?? '')
	|| arrayThrow.payload.arrayDescriptorId !== 'represented-array:Array<Int>'
	|| !/^sha256:[0-9a-f]{64}$/.test(arrayThrow.payload.arrayDescriptorRevision ?? '')
	|| arrayThrow.payload.conversion !== 'box-represented-array-throw-carrier'
	|| arrayThrow.proofId !== 'represented-array-throw-control-v1'
	|| arrayThrow.runtimeTags.join(',') !== 'Dynamic,Array') {
	throw new Error('public inspection did not validate the exact nested Array<Int> throw crossing')
}
const arrayRepresentation = report.lowering.representation.decisions.find(decision =>
	decision.id === arrayThrow.payload.inputRepresentationId)
const arrayDescriptor = report.lowering.representation.representedArrays.find(descriptor =>
	descriptor.id === arrayThrow.payload.arrayDescriptorId)
if (arrayRepresentation?.revision !== arrayThrow.payload.representationRevision
	|| arrayRepresentation?.arrayDescriptorId !== arrayDescriptor?.id
	|| arrayRepresentation?.arrayDescriptorRevision !== arrayDescriptor?.revision
	|| arrayDescriptor?.revision !== arrayThrow.payload.arrayDescriptorRevision
	|| arrayDescriptor?.elementRepresentationId !== 'representation:Int:array-element') {
	throw new Error('public inspection did not validate the represented-array revision graph')
}
if (arrayThrow.payload.arrayLiteralProducerId != null
	|| arrayThrow.payload.arrayLiteralProducerPlanRevision != null) {
	throw new Error('public inspection attached a direct-literal producer to the existing local Array<Int> throw')
}
const literalProducer = report.lowering.arrayLiteralProducers.find(producer =>
	producer.functionId.includes('|function|nestedArrayLiteralThrowClosure|')
	&& producer.functionId.includes('|nested-function|'))
const literalThrow = report.lowering.controls.find(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedArrayLiteralThrowClosure|')
	&& control.functionId.includes('|nested-function|'))
if (report.lowering.arrayLiteralProducerModel !== 'ocaml-represented-array-literal-producer-v3'
	|| !/^sha256:[0-9a-f]{64}$/.test(report.lowering.arrayLiteralProducerRevision ?? '')
	|| literalProducer?.elements.length !== 2
	|| literalProducer.evaluationSchedule.map(step => step.kind).join(',')
		!== 'create-array,evaluate-element,store-element,evaluate-element,store-element,result-array'
	|| literalThrow?.payload?.arrayLiteralProducerId !== literalProducer.id
	|| !/^sha256:[0-9a-f]{64}$/.test(literalThrow.payload.arrayLiteralProducerPlanRevision ?? '')
	|| literalThrow.functionId !== literalProducer.functionId
	|| literalThrow.programRevision !== literalProducer.programRevision
	|| literalThrow.bodyRevision !== literalProducer.bodyRevision
	|| literalThrow.pipelineRevision !== literalProducer.pipelineRevision
	|| literalThrow.payload.inputRepresentationId !== literalProducer.resultRepresentationId
	|| literalThrow.payload.representationRevision !== literalProducer.resultRepresentationRevision
	|| literalThrow.payload.arrayDescriptorId !== literalProducer.arrayDescriptorId
	|| literalThrow.payload.arrayDescriptorRevision !== literalProducer.arrayDescriptorRevision) {
	throw new Error('public inspection did not validate the direct Array<Int> literal producer/control link')
}
const stringLiteralProducer = report.lowering.arrayLiteralProducers.find(producer =>
	producer.functionId.includes('|function|nestedStringArrayLiteralThrowClosure|')
	&& producer.functionId.includes('|nested-function|'))
const stringLiteralThrow = report.lowering.controls.find(control =>
	control.kind === 'throw'
	&& control.functionId.includes('|function|nestedStringArrayLiteralThrowClosure|')
	&& control.functionId.includes('|nested-function|'))
if (stringLiteralProducer?.arraySemanticTypeId !== 'Array<String>'
	|| stringLiteralProducer.arrayCarrierTypeId !== 'string HxArray.t'
	|| stringLiteralProducer.elementSemanticTypeId !== 'String'
	|| stringLiteralProducer.elementCarrierTypeId !== 'string'
	|| stringLiteralProducer.elementRepresentationId !== 'representation:String:array-element'
	|| stringLiteralProducer.proofId !== 'direct-array-string-literal-construction-v1'
	|| stringLiteralProducer.elements.length !== 2
	|| stringLiteralProducer.evaluationSchedule.map(step => step.kind).join(',')
		!== 'create-array,evaluate-element,store-element,evaluate-element,store-element,result-array'
	|| stringLiteralThrow?.payload?.arrayLiteralProducerId !== stringLiteralProducer.id
	|| !/^sha256:[0-9a-f]{64}$/.test(stringLiteralThrow.payload.arrayLiteralProducerPlanRevision ?? '')
	|| stringLiteralThrow.functionId !== stringLiteralProducer.functionId
	|| stringLiteralThrow.programRevision !== stringLiteralProducer.programRevision
	|| stringLiteralThrow.bodyRevision !== stringLiteralProducer.bodyRevision
	|| stringLiteralThrow.pipelineRevision !== stringLiteralProducer.pipelineRevision
	|| stringLiteralThrow.payload.inputSemanticTypeId !== 'Array<String>'
	|| stringLiteralThrow.payload.inputCarrierTypeId !== 'string HxArray.t'
	|| stringLiteralThrow.payload.inputRepresentationId !== stringLiteralProducer.resultRepresentationId
	|| stringLiteralThrow.payload.representationRevision !== stringLiteralProducer.resultRepresentationRevision
	|| stringLiteralThrow.payload.arrayDescriptorId !== stringLiteralProducer.arrayDescriptorId
	|| stringLiteralThrow.payload.arrayDescriptorRevision !== stringLiteralProducer.arrayDescriptorRevision) {
	throw new Error('public inspection did not validate the direct Array<String> literal producer/control link')
}
const nominalCall = report.lowering.calls.find(call =>
	call.kind === 'typed-function-value'
	&& call.functionId.includes('|function|nestedNominalClosure|'))
if (nominalCall?.proofId !== 'typed-function-value-signature-matrix-v1:(Bool)->_Main.NestedReturnBox'
	|| nominalCall.result?.inputRepresentationId !== 'representation:_Main.NestedReturnBox:internal-value'
	|| nominalCall.result?.inputCarrierTypeId !== 'nestedreturnbox_t'
	|| nominalCall.result?.outputRepresentationId !== nominalCall.result.inputRepresentationId
	|| nominalCall.result?.outputCarrierTypeId !== nominalCall.result.inputCarrierTypeId) {
	throw new Error('public inspection did not expose the exact nominal function-value result boundary')
}
NODE

for mutation in duplicate missing stale-program carrier representation conversion callable-owner instance-source instance-callable-owner; do
	invalid_output="$INVALID_RESULT_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const targetsInstance = mutation === 'instance-source' || mutation === 'instance-callable-owner'
const index = report.functionResultBoundaries.findIndex(entry => targetsInstance
	? entry.functionId.includes('sys.io.Stdio|OcamlStdioOutput|instance|function|writeBytes|')
	: entry.functionId.includes('StringTools|StringTools|static|function|_hexValue|'))
if (index < 0) {
	throw new Error('missing selected function-result boundary to corrupt')
}
const boundary = report.functionResultBoundaries[index]
switch (mutation) {
	case 'duplicate':
		report.functionResultBoundaries.splice(index + 1, 0, structuredClone(boundary))
		break
	case 'missing':
		report.functionResultBoundaries.splice(index, 1)
		break
	case 'stale-program':
		boundary.programRevision = 'stale-program-revision'
		break
	case 'carrier':
		boundary.result.outputCarrierTypeId = 'Obj.t'
		break
	case 'representation':
		boundary.result.outputRepresentationId = 'representation:Int:captured-local-storage'
		break
	case 'conversion':
		boundary.result.conversion = 'checked-unbox-nullable-int'
		break
	case 'callable-owner':
		boundary.source = 'callable-boundary'
		boundary.callableBoundaryId = 'callable-boundary:missing'
		boundary.proofId = 'callable-function-result-boundary-v1'
		break
	case 'instance-source':
		boundary.source = 'static-inline-exact-int-declaration'
		boundary.proofId = 'static-inline-exact-int-function-result-v1'
		break
	case 'instance-callable-owner':
		boundary.source = 'callable-boundary'
		boundary.callableBoundaryId = 'callable-boundary:missing'
		boundary.proofId = 'callable-function-result-boundary-v1'
		break
	default:
		throw new Error(`unsupported corruption ${mutation}`)
}
report.functionResultBoundaryCount = report.functionResultBoundaries.length
report.functionResultBoundaryRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.functionResultBoundaries)).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	invalid_log="$INVALID_RESULT_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted corrupted function-result $mutation evidence" >&2
		exit 1
	fi
	if ! grep -Eiq 'function-result|function result' "$invalid_log"; then
		echo "The public inspector rejected corrupted function-result $mutation evidence for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

for mutation in duplicate missing-family edited-count stale-revision; do
	invalid_output="$INVALID_ADMISSION_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const admission = report.controlAdmissions.find(entry =>
	entry.functionId.includes('haxe.NativeStackTrace|NativeStackTrace|static|function|parseFileLine|'))
const family = admission?.families?.find(entry => entry.family === 'return')
if (family?.status !== 'admitted') {
	throw new Error('missing admitted nullable anonymous return family to corrupt')
}
switch (mutation) {
	case 'duplicate':
		report.controlAdmissions.push(structuredClone(report.controlAdmissions[0]))
		report.controlAdmissionCount = report.controlAdmissions.length
		break
	case 'missing-family':
		admission.families.pop()
		break
	case 'edited-count':
		family.occurrenceCount += 1
		break
	case 'stale-revision':
		admission.revision = `sha256:${'0'.repeat(64)}`
		break
	default:
		throw new Error(`unsupported corruption ${mutation}`)
}
report.controlAdmissionRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.controlAdmissions)).digest('hex')}`
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
	invalid_log="$INVALID_ADMISSION_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted corrupted control-admission $mutation evidence" >&2
		exit 1
	fi
	if ! grep -Eq 'Control admission|Control-admission|control admission|control-admission|ocaml-control-admission' "$invalid_log"; then
		echo "The public inspector rejected corrupted control-admission $mutation evidence for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

for mutation in semantic carrier representation layout proof; do
	invalid_output="$INVALID_NOMINAL_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls?.find(item =>
	item.kind === 'return'
	&& item.functionId.includes('|function|nestedNominalClosure|')
	&& item.functionId.includes('|nested-function|'))
if (control?.payload?.nominalRepresentation == null) {
	throw new Error('missing nested nominal return proof to corrupt')
}
switch (mutation) {
	case 'semantic':
		control.payload.inputSemanticTypeId = '_Main.ForeignBox'
		control.payload.outputSemanticTypeId = '_Main.ForeignBox'
		break
	case 'carrier':
		control.payload.inputCarrierTypeId = 'foreignbox_t'
		control.payload.outputCarrierTypeId = 'foreignbox_t'
		break
	case 'representation':
		control.payload.inputRepresentationId = 'representation:_Main.ForeignBox:internal-value'
		control.payload.outputRepresentationId = 'representation:_Main.ForeignBox:internal-value'
		break
	case 'layout':
		control.payload.nominalRepresentation.layoutRevision = `sha256:${'0'.repeat(64)}`
		break
	case 'proof':
		control.proofId = 'wrong-nominal-return-proof'
		control.payload.proofId = 'wrong-nominal-return-proof'
		break
	default:
		throw new Error(`unsupported corruption ${mutation}`)
}
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
	haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
		"$invalid_output/ocaml_lowering_report.json"
	invalid_log="$INVALID_NOMINAL_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted a nested nominal return with corrupted $mutation metadata" >&2
		exit 1
	fi
	if ! grep -Fq 'Control decision' "$invalid_log"; then
		echo "The public inspector rejected corrupted $mutation metadata for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

for mutation in semantic carrier representation representation-revision descriptor descriptor-revision conversion tags proof program body binding; do
	invalid_output="$INVALID_ARRAY_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const control = report.controls?.find(item =>
	item.kind === 'throw'
	&& item.functionId.includes('|function|nestedArrayThrowClosure|')
	&& item.functionId.includes('|nested-function|'))
if (control?.payload == null) {
	throw new Error('missing nested Array<Int> throw proof to corrupt')
}
switch (mutation) {
	case 'semantic':
		control.payload.inputSemanticTypeId = 'Array<String>'
		control.payload.outputSemanticTypeId = 'Array<String>'
		break
	case 'carrier':
		control.payload.inputCarrierTypeId = 'Obj.t'
		control.payload.outputCarrierTypeId = 'Obj.t'
		break
	case 'representation':
		control.payload.inputRepresentationId = 'representation:Array<Int>:captured-local-storage'
		control.payload.outputRepresentationId = 'representation:Array<Int>:captured-local-storage'
		break
	case 'representation-revision':
		control.payload.representationRevision = `sha256:${'0'.repeat(64)}`
		break
	case 'descriptor':
		control.payload.arrayDescriptorId = 'represented-array:Array<String>'
		break
	case 'descriptor-revision':
		control.payload.arrayDescriptorRevision = `sha256:${'0'.repeat(64)}`
		break
	case 'conversion':
		control.payload.conversion = 'box-nominal-throw-carrier'
		break
	case 'tags':
		control.runtimeTags = ['Dynamic']
		break
	case 'proof':
		control.proofId = 'wrong-array-throw-proof'
		control.payload.proofId = 'wrong-array-throw-proof'
		break
	case 'program':
		control.programRevision = 'stale-program-revision'
		break
	case 'body':
		control.bodyRevision = '0:stale-body-revision'
		break
	case 'binding':
		control.pipelineRevision = 'ocaml-nested-function-plans-v7'
		break
	default:
		throw new Error(`unsupported corruption ${mutation}`)
}
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
	haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
		"$invalid_output/ocaml_lowering_report.json"
	invalid_log="$INVALID_ARRAY_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted an exact Array<Int> throw with corrupted $mutation metadata" >&2
		exit 1
	fi
	if ! grep -Fq 'Control decision' "$invalid_log"; then
		echo "The public inspector rejected corrupted Array<Int> $mutation metadata for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

for mutation in missing-producer producer-id reordered-elements duplicated-element reordered-schedule stale-binding control-plan-revision; do
	invalid_output="$INVALID_LITERAL_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const producerIndex = report.arrayLiteralProducers?.findIndex(item =>
	item.functionId.includes('|function|nestedArrayLiteralThrowClosure|')
	&& item.functionId.includes('|nested-function|'))
const control = report.controls?.find(item =>
	item.kind === 'throw'
	&& item.functionId.includes('|function|nestedArrayLiteralThrowClosure|')
	&& item.functionId.includes('|nested-function|'))
if (producerIndex == null || producerIndex < 0 || control?.payload == null) {
	throw new Error('missing direct Array<Int> literal producer/control proof to corrupt')
}
const producer = report.arrayLiteralProducers[producerIndex]
switch (mutation) {
	case 'missing-producer':
		report.arrayLiteralProducers.splice(producerIndex, 1)
		report.arrayLiteralProducerCount = report.arrayLiteralProducers.length
		break
	case 'producer-id':
		producer.id = `array-literal-producer:${'0'.repeat(32)}`
		break
	case 'reordered-elements':
		producer.elements.reverse()
		break
	case 'duplicated-element':
		producer.elements[1] = {...producer.elements[0]}
		break
	case 'reordered-schedule':
		[producer.evaluationSchedule[1], producer.evaluationSchedule[2]] = [producer.evaluationSchedule[2], producer.evaluationSchedule[1]]
		break
	case 'stale-binding':
		producer.bodyRevision = `0:${'0'.repeat(64)}`
		break
	case 'control-plan-revision':
		control.payload.arrayLiteralProducerPlanRevision = `sha256:${'0'.repeat(64)}`
		break
	default:
		throw new Error(`unsupported corruption ${mutation}`)
}
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
	if [ "$mutation" = "control-plan-revision" ]; then
		haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
			"$invalid_output/ocaml_lowering_report.json"
	fi
	invalid_log="$INVALID_LITERAL_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted a direct Array<Int> literal producer with corrupted $mutation metadata" >&2
		exit 1
	fi
	if ! grep -Eq 'Array literal producer|Array-literal producer|array-literal producer|array literal producer|ocaml-array-literal|Control decision' "$invalid_log"; then
		echo "The public inspector rejected corrupted direct-literal $mutation metadata for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

for mutation in string-missing-producer string-control-plan-revision; do
	invalid_output="$INVALID_LITERAL_ROOT/$mutation"
	cp -R out "$invalid_output"
	node - "$invalid_output/ocaml_lowering_report.json" "$mutation" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const mutation = process.argv[3]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const producerIndex = report.arrayLiteralProducers?.findIndex(item =>
	item.functionId.includes('|function|nestedStringArrayLiteralThrowClosure|')
	&& item.functionId.includes('|nested-function|'))
const control = report.controls?.find(item =>
	item.kind === 'throw'
	&& item.functionId.includes('|function|nestedStringArrayLiteralThrowClosure|')
	&& item.functionId.includes('|nested-function|'))
if (producerIndex == null || producerIndex < 0 || control?.payload == null) {
	throw new Error('missing direct Array<String> literal producer/control proof to corrupt')
}
if (mutation === 'string-missing-producer') {
	report.arrayLiteralProducers.splice(producerIndex, 1)
	report.arrayLiteralProducerCount = report.arrayLiteralProducers.length
} else if (mutation === 'string-control-plan-revision') {
	control.payload.arrayLiteralProducerPlanRevision = `sha256:${'0'.repeat(64)}`
} else {
	throw new Error(`unsupported corruption ${mutation}`)
}
fs.writeFileSync(path, JSON.stringify(report, null, 2) + '\n')
NODE
	if [ "$mutation" = "string-control-plan-revision" ]; then
		haxe -cp "$ROOT/scripts/ci" -cp "$ROOT/packages/reflaxe.ocaml/src" --run RecomputeLoweringControlRevision \
			"$invalid_output/ocaml_lowering_report.json"
	fi
	invalid_log="$INVALID_LITERAL_ROOT/$mutation.log"
	if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
		echo "The public inspector accepted a direct Array<String> literal producer with corrupted $mutation metadata" >&2
		exit 1
	fi
	if ! grep -Eq 'Array literal producer|Array-literal producer|array-literal producer|array literal producer|ocaml-array-literal|Control decision' "$invalid_log"; then
		echo "The public inspector rejected corrupted Array<String> $mutation metadata for an unrelated reason" >&2
		cat "$invalid_log" >&2
		exit 1
	fi
done

echo "REFLAXE_OCAML_EARLY_RETURN_CONTROL_FIXTURE:PASS controls=56 function_results=55 producers=4"
