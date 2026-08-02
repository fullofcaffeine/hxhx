'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

/**
 * Proves that an inlined Haxe Dynamic parameter keeps one sealed Obj.t carrier.
 *
 * The source deliberately sends String, Int, Float, Bool, null, a class, and an
 * anonymous structure through an ordinary Haxe call, a typed native call, and
 * Std.string. This check connects the lowered evidence to the generated OCaml:
 * concrete values enter Dynamic once, Bool uses its distinguishable runtime
 * box, and every later consumer preserves the same carrier.
 */
const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
const generatedMain = fs.readFileSync('out/Main.ml', 'utf8')
const generatedTypeRegistry = fs.readFileSync('out/HxTypeRegistry.ml', 'utf8')
const repositoryRoot = path.resolve(__dirname, '../../../..')

assert.equal(report.schemaVersion, 51)
assert.equal(report.callModel, 'typed-ocaml-directional-call-boundary-v19')
assert.equal(
	report.representationScope,
	'exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-array-int-locals-monomorphic-class-dynamic-internal-v14',
)
assert.equal(report.localConversionModel, 'typed-ocaml-local-carrier-conversions-v3')
assert.equal(report.unsafeOperationCompleteness, 'exact-null-int-null-bool-inline-dynamic-and-enum-to-dynamic-local-and-container-slices')

const dynamicRepresentations = report.representations.filter((representation) => representation.semanticTypeId === 'Dynamic')
assert.equal(dynamicRepresentations.length, 1, 'Dynamic must have one selected representation')
assert.deepEqual(dynamicRepresentations[0], {
	...dynamicRepresentations[0],
	carrierTypeId: 'Obj.t',
	storageMutationPolicy: 'immutable-binding',
	implicitDefaultPolicy: 'not-admitted',
	id: 'representation:Dynamic:internal-value',
	semanticTypeId: 'Dynamic',
	aliasingPolicy: 'dynamic-payload-aliases',
	nullPolicy: 'runtime-sentinel',
	identityPolicy: 'dynamic-payload-identity',
	key: 'Dynamic|internal-value',
	domain: 'internal-value',
	boxingPolicy: 'dynamic-carrier',
	valueMutationPolicy: 'dynamic-payload-mutation',
})
assert.equal(dynamicRepresentations[0].proof.id, 'dynamic-obj-carrier-v1')
assert.deepEqual(dynamicRepresentations[0].profileEligibility, ['metal', 'portable'])

const dynamicConversions = report.localConversions.filter((conversion) => conversion.outputSemanticTypeId === 'Dynamic')
const conversionsByKind = new Map()
for (const conversion of dynamicConversions) {
	if (!conversionsByKind.has(conversion.conversion))
		conversionsByKind.set(conversion.conversion, [])
	conversionsByKind.get(conversion.conversion).push(conversion)

	const expected = {
		'box-concrete-to-dynamic': ['dynamic-box-concrete-value-v1', 'Obj.t'],
		'box-exact-bool-to-dynamic': ['dynamic-box-exact-bool-v1', 'Obj.t'],
		'preserve-dynamic-carrier': ['dynamic-carrier-preserve-v1', 'Obj.t'],
	}[conversion.conversion]
	assert(expected, `Unexpected Dynamic conversion ${conversion.conversion}`)
	assert.equal(conversion.proofId, expected[0])
	assert.equal(conversion.role, 'initializer')
	assert.equal(conversion.outputCarrierTypeId, expected[1])
	assert.deepEqual(conversion.profileEligibility, ['metal', 'portable'])
}

assert(conversionsByKind.has('box-concrete-to-dynamic'))
assert(conversionsByKind.has('box-exact-bool-to-dynamic'))
assert(conversionsByKind.has('preserve-dynamic-carrier'))
assert.deepEqual(
	[...new Set(conversionsByKind.get('box-concrete-to-dynamic').map((conversion) => conversion.inputSemanticTypeId))].sort(),
	['Float', 'Int', 'String', '_Main.SampleValue', '{ label : String }'],
)
assert.deepEqual(
	conversionsByKind.get('box-exact-bool-to-dynamic').map((conversion) => conversion.inputSemanticTypeId),
	['Bool'],
)
assert.deepEqual(
	conversionsByKind.get('preserve-dynamic-carrier').map((conversion) => conversion.inputSemanticTypeId),
	['Dynamic'],
)

const dynamicUnsafeOperations = report.unsafeOperations.filter((operation) => operation.outputSemanticTypeId === 'Dynamic')
assert.equal(dynamicUnsafeOperations.length, dynamicConversions.length - conversionsByKind.get('preserve-dynamic-carrier').length)
for (const operation of dynamicUnsafeOperations) {
	const expectedProof = {
		'obj-repr-concrete-to-dynamic': 'dynamic-box-concrete-value-v1',
		'box-exact-bool-to-dynamic': 'dynamic-box-exact-bool-v1',
	}[operation.operation]
	assert(expectedProof, `Unexpected Dynamic unsafe operation ${operation.operation}`)
	assert.equal(operation.proofId, expectedProof)
	assert.equal(operation.outputCarrierTypeId, 'Obj.t')
	assert.equal(operation.pipelineRevision, 'ocaml-function-plans-v64')
}

const dynamicCallableBoundaries = report.callableBoundaries.filter((boundary) =>
	['ordinaryText', 'nativeText'].includes(boundary.sourceFieldName),
)
assert.equal(dynamicCallableBoundaries.length, 2)
for (const boundary of dynamicCallableBoundaries) {
	assert.equal(boundary.pipelineRevision, 'ocaml-function-plans-v64')
	assert.equal(boundary.arguments.length, 1)
	assert.deepEqual(boundary.arguments[0], {
		parameterOptional: false,
		inputRepresentationId: 'representation:Dynamic:internal-value',
		outputSemanticTypeId: 'Dynamic',
		proofClaim: boundary.arguments[0].proofClaim,
		inputCarrierTypeId: 'Obj.t',
		proofId: 'identity-call-carrier-v1',
		outputRepresentationId: 'representation:Dynamic:internal-value',
		conversion: 'identity',
		inputSemanticTypeId: 'Dynamic',
		index: 0,
		outputCarrierTypeId: 'Obj.t',
	})
}

const dynamicCalls = report.calls.filter((call) => ['ordinaryText', 'nativeText'].includes(call.sourceFieldName))
assert.equal(dynamicCalls.length, 16)
for (const call of dynamicCalls) {
	assert.equal(call.arguments.length, 1)
	assert.equal(call.arguments[0].conversion, 'preserve-dynamic-carrier')
	assert.equal(call.arguments[0].proofId, 'dynamic-call-carrier-preserve-v1')
	assert.equal(call.arguments[0].inputSemanticTypeId, 'Dynamic')
	assert.equal(call.arguments[0].inputCarrierTypeId, 'Obj.t')
	assert.equal(call.arguments[0].outputSemanticTypeId, 'Dynamic')
	assert.equal(call.arguments[0].outputCarrierTypeId, 'Obj.t')
}

assert.match(generatedMain, /let ordinaryText = fun \(value : Obj\.t\)/)
assert.match(generatedMain, /let nativeText = fun \(value : Obj\.t\)/)
assert.match(generatedMain, /let value = Obj\.repr "text"/)
assert.match(generatedMain, /let value = Obj\.repr 7/)
assert.match(generatedMain, /let value = Obj\.repr 1\.5/)
assert.match(generatedMain, /let value = HxRuntime\.box_bool true/)
assert.match(generatedMain, /let value = \(Obj\.magic \(HxRuntime\.hx_null\) : Obj\.t\)/)
assert.match(generatedMain, /let value = Obj\.repr \(samplevalue_create/)
assert.match(generatedMain, /let value = Obj\.repr \(let __anonymous_value_/)
assert.match(generatedMain, /ordinaryText __call_arg_/)
assert.match(generatedMain, /nativeText __call_arg_/)
assert.match(generatedMain, /HxSys\.printlnValue v/)
assert(!generatedMain.includes('print_endline'), 'Generated application code must use the typed Haxe Sys facade')
assert.match(
	generatedTypeRegistry,
	/HxDynamic\.register_class_stringifier "_Main\.SampleValue" \(fun value -> Main\.samplevalue_toString \(Obj\.obj value\) \(\)\)/,
)

const builderSource = fs.readFileSync(
	path.join(repositoryRoot, 'packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx'),
	'utf8',
)
const hxRuntimeSource = fs.readFileSync(path.join(repositoryRoot, 'packages/reflaxe.ocaml/std/runtime/HxRuntime.ml'), 'utf8')
const callStackSource = fs.readFileSync(
	path.join(repositoryRoot, 'packages/reflaxe.ocaml/std/runtime/haxe_CallStack.ml'),
	'utf8',
)
assert(!builderSource.includes('isBuilderOwnedSysCall'))
assert(!builderSource.includes('case "print", "println"'))
assert(!hxRuntimeSource.includes('dynamic_toStdString'), 'HxRuntime must not retain a competing Dynamic string owner')
assert(callStackSource.includes('HxDynamic.toStdString'), 'Call-stack text must use the shared Dynamic string owner')

console.log('INLINE_DYNAMIC_CARRIER_PLAN:PASS')
