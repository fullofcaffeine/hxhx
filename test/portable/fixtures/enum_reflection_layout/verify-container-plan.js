#!/usr/bin/env node

const assert = require('node:assert/strict')
const childProcess = require('node:child_process')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const fixtureRoot = __dirname
const repoRoot = path.resolve(fixtureRoot, '../../../..')

/** Reads one compiler-owned JSON report from the fixture output directory. */
function readReport(name) {
	return JSON.parse(fs.readFileSync(path.join(fixtureRoot, 'out', name), 'utf8'))
}

const lowering = readReport('ocaml_lowering_report.json')
const runtime = readReport('ocaml_runtime_requirement_report.json')
const generated = fs.readFileSync(path.join(fixtureRoot, 'out', 'Main.ml'), 'utf8')
const builderSource = fs.readFileSync(
	path.join(repoRoot, 'packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx'),
	'utf8'
)
const arrayElementBuilder = builderSource.match(
	/function buildArrayLiteralElement\([\s\S]*?\n\t}\n\n\t\/\*\*/
)
assert.notEqual(arrayElementBuilder, null, 'could not locate the array-element syntax boundary')
assert.match(arrayElementBuilder[0], /if \(plan == null\)\s*\n\s*return containerElementInvariant/,
	'array syntax must stop when its complete container plan is absent')
assert.doesNotMatch(arrayElementBuilder[0], /fromDirectValue/,
	'array syntax must consume the sealed enum identity instead of classifying the typed constructor again')

const conversions = lowering.containerElementConversions
assert.equal(lowering.schemaVersion, 83)
assert.equal(conversions.length, 4,
	'the method-local and static-initializer enum values should each have one sealed conversion')
assert.deepEqual(conversions.map(entry => entry.elementIndex).sort(), [0, 0, 1, 1])
assert.deepEqual(conversions.map(entry => entry.containerOrdinal), [0, 0, 0, 0],
	'each pair should share the first structural array occurrence in its own typed root')
const standaloneConversions = conversions.filter(entry => entry.functionId.startsWith('standalone:field-initializer:'))
const functionConversions = conversions.filter(entry => !entry.functionId.startsWith('standalone:'))
assert.equal(standaloneConversions.length, 2,
	'the static field initializer should publish both independently planned conversions')
assert.equal(functionConversions.length, 2,
	'the method body should continue to publish both independently planned conversions')
assert.deepEqual(lowering.containerElementRequiredConversionIds, conversions.map(entry => entry.id),
	'the independent typed-body inventories should require exactly the four sealed conversions')

for (const conversion of conversions) {
	assert.equal(conversion.role, 'array-literal-dynamic-element')
	assert.equal(conversion.inputSemanticTypeId, 'MixedShape')
	assert.equal(conversion.inputCarrierTypeId, 'haxe-enum-native-variant-carrier-v1:MixedShape')
	assert.equal(conversion.outputSemanticTypeId, 'Dynamic')
	assert.equal(conversion.outputCarrierTypeId, 'Obj.t')
	assert.equal(conversion.conversion, 'box-exact-enum-to-dynamic')
	assert.equal(conversion.proofId, 'dynamic-array-element-box-exact-enum-v1')
	assert.equal(conversion.unsafeOperation.conversionId, conversion.id)
}

const unsafeByConversion = new Map(lowering.unsafeOperations
	.filter(entry => entry.operation === 'box-exact-enum-to-dynamic')
	.map(entry => [entry.conversionId, entry]))
for (const conversion of conversions)
	assert.equal(conversion.unsafeOperation.id, unsafeByConversion.get(conversion.id).id)

const requirementByDecision = new Map(runtime.requirements
	.filter(entry => entry.semanticCapability === 'haxe-enum-dynamic-box')
	.map(entry => [entry.decisionId, entry]))
for (const conversion of conversions) {
	const requirement = requirementByDecision.get(conversion.id)
	assert(requirement, `missing HxEnum runtime requirement for ${conversion.id}`)
	assert.deepEqual(requirement.rootModules, ['HxEnum'])
	assert.equal(requirement.subject.id, 'MixedShape')
}

const functionStart = generated.indexOf('let dynamicArrayCases')
const functionEnd = generated.indexOf('let factoryCases', functionStart)
assert(functionStart >= 0 && functionEnd > functionStart, 'generated output lost the dynamic array fixture boundary')
const dynamicArraySyntax = generated.slice(functionStart, functionEnd)
const generatedBoxes = dynamicArraySyntax.match(/HxEnum\.box_if_needed "MixedShape" \(Obj\.repr/g) || []
assert.equal(generatedBoxes.length, functionConversions.length,
	'method syntax should apply exactly its two sealed array-element conversions')
const staticStart = generated.indexOf('let staticDynamicValues')
const staticEnd = generated.indexOf('let staticDynamicArrayCases', staticStart)
assert(staticStart >= 0 && staticEnd > staticStart, 'generated output lost the static array initializer boundary')
const staticArraySyntax = generated.slice(staticStart, staticEnd)
const generatedStaticBoxes = staticArraySyntax.match(/HxEnum\.box_if_needed "MixedShape" \(Obj\.repr/g) || []
assert.equal(generatedStaticBoxes.length, standaloneConversions.length,
	'static initializer syntax should apply exactly its two sealed array-element conversions')

/**
 * Runs the public inspection command against one output directory.
 *
 * The inspector is the independent consumer used by release tooling. A valid
 * result proves that the compiler did not merely write self-consistent fields
 * which only this fixture understands.
 */
function inspect(outputDirectory) {
	return childProcess.spawnSync('haxe', [
		'-cp', 'packages/reflaxe.ocaml/src',
		'--macro', 'nullSafety("reflaxe.ocaml")',
		'--run', 'reflaxe.ocaml.tooling.ReflaxeOcamlRun',
		'inspect',
		'--project', fixtureRoot,
		'--output', outputDirectory,
		'--require-lowering',
		'--json'
	], {
		cwd: repoRoot,
		encoding: 'utf8'
	})
}

const inspection = inspect(path.join(fixtureRoot, 'out'))
assert.equal(inspection.status, 0, `public inspection rejected the valid container plan: ${inspection.stdout}${inspection.stderr}`)
const inspectionReport = JSON.parse(inspection.stdout)
assert.equal(inspectionReport.schemaVersion, 46)
assert.equal(inspectionReport.lowering.containerElementConversions.length, conversions.length)
assert.deepEqual(inspectionReport.lowering.containerElementRequiredConversionIds, conversions.map(entry => entry.id))

const tamperRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-enum-container-tamper-'))
const tamperOut = path.join(tamperRoot, 'out')
try {
	/**
	 * Restores the valid output before one independent corruption case.
	 *
	 * Each case changes one owner only, so rejection proves that the named
	 * relationship is checked instead of inheriting damage from an earlier case.
	 */
	function resetTamperOutput() {
		fs.rmSync(tamperOut, { recursive: true, force: true })
		fs.cpSync(path.join(fixtureRoot, 'out'), tamperOut, {
			recursive: true,
			filter: source => path.basename(source) !== '_build'
		})
	}

	/** Mutates one copied lowering report and requires the public inspector to reject it. */
	function expectLoweringRejection(label, pattern, mutate) {
		resetTamperOutput()
		const reportPath = path.join(tamperOut, 'ocaml_lowering_report.json')
		const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
		mutate(report)
		fs.writeFileSync(reportPath, JSON.stringify(report, null, 2))
		const recompute = childProcess.spawnSync('haxe', [
			'-cp', path.join(repoRoot, 'scripts/ci'),
			'--run', 'RecomputeLoweringContainerRevisions',
			reportPath
		], {
			cwd: repoRoot,
			encoding: 'utf8'
		})
		assert.equal(recompute.status, 0,
			`could not refresh lowering section revisions for ${label}: ${recompute.stdout}${recompute.stderr}`)
		const result = inspect(tamperOut)
		assert.notEqual(result.status, 0, `public inspection accepted ${label}`)
		assert.match(result.stdout + result.stderr, pattern)
	}

	expectLoweringRejection('a completely omitted required container conversion', /required container-element conversion inventory.*does not match/i, report => {
		const removed = report.containerElementConversions.shift()
		report.containerElementConversionCount = report.containerElementConversions.length
		report.unsafeOperations = report.unsafeOperations.filter(entry => entry.conversionId !== removed.id)
		report.unsafeOperationCount = report.unsafeOperations.length
		report.runtimeRequirements = report.runtimeRequirements.filter(entry => entry.decisionId !== removed.id)
		report.runtimeRequirementCount = report.runtimeRequirements.length
	})
	expectLoweringRejection('a duplicated container conversion', /duplicate identity/, report => {
		report.containerElementConversions.push(report.containerElementConversions[0])
		report.containerElementConversionCount = report.containerElementConversions.length
	})
	expectLoweringRejection('a stale container occurrence', /does not match its retained function/, report => {
		const conversion = report.containerElementConversions[0]
		const operation = report.unsafeOperations.find(entry => entry.conversionId === conversion.id)
		conversion.source.min += 1
		conversion.unsafeOperation.source.min += 1
		operation.source.min += 1
	})
	expectLoweringRejection('a stale container structural ordinal', /does not match its retained function/, report => {
		report.containerElementConversions[0].containerOrdinal += 1
	})
	expectLoweringRejection('a standalone conversion using the function pipeline revision',
		/invalid exact enum-to-Dynamic array contract/, report => {
			const standalone = report.containerElementConversions.find(entry => entry.functionId.startsWith('standalone:'))
			standalone.pipelineRevision = 'ocaml-function-plans-v66'
		})
	expectLoweringRejection('a corrupt container carrier', /invalid exact enum-to-Dynamic array contract/, report => {
		report.containerElementConversions[0].inputCarrierTypeId = 'haxe-enum-native-variant-carrier-v1:OtherEnum'
	})
	expectLoweringRejection('an empty container conversion reason', /invalid exact enum-to-Dynamic array contract/, report => {
		report.containerElementConversions[0].reason = ''
	})
	expectLoweringRejection('an empty container conversion proof claim', /invalid exact enum-to-Dynamic array contract/, report => {
		report.containerElementConversions[0].proofClaim = ''
	})
	expectLoweringRejection('a container conversion without its HxEnum requirement', /refers to missing runtime requirement/, report => {
		const conversion = report.containerElementConversions[0]
		const requirementId = `${conversion.id}:runtime:haxe-enum-dynamic-box`
		report.runtimeRequirements = report.runtimeRequirements.filter(entry => entry.id !== requirementId)
		report.runtimeRequirementCount = report.runtimeRequirements.length
	})
} finally {
	fs.rmSync(tamperRoot, { recursive: true, force: true })
}

console.log('REFLAXE_OCAML_ENUM_DYNAMIC_CONTAINER_PLAN:PASS')
