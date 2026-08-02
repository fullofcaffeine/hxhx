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
	return JSON.parse(fs.readFileSync(`out/${name}`, 'utf8'))
}

const lowering = readReport('ocaml_lowering_report.json')
const runtime = readReport('ocaml_runtime_requirement_report.json')
const generated = fs.readFileSync('out/Main.ml', 'utf8')

const enumConversions = lowering.localConversions.filter(entry => entry.conversion === 'box-exact-enum-to-dynamic')
assert.equal(enumConversions.length, 4, 'each exact enum initializer should publish one sealed enum-to-Dynamic conversion')

const conversionIds = new Set(enumConversions.map(entry => entry.id))
const enumUnsafe = lowering.unsafeOperations.filter(entry =>
	entry.operation === 'box-exact-enum-to-dynamic' && conversionIds.has(entry.conversionId))
assert.equal(enumUnsafe.length, enumConversions.length, 'each enum conversion should own its Obj.repr plus HxEnum proof record')

const unsafeByConversion = new Map(enumUnsafe.map(entry => [entry.conversionId, entry]))
for (const conversion of enumConversions) {
	assert.equal(conversion.inputSemanticTypeId, 'MyEnum')
	assert.equal(conversion.inputCarrierTypeId, 'haxe-enum-native-variant-carrier-v1:MyEnum')
	assert.equal(conversion.outputSemanticTypeId, 'Dynamic')
	assert.equal(conversion.outputCarrierTypeId, 'Obj.t')
	assert.equal(conversion.role, 'initializer')
	assert.equal(conversion.unsafeOperation.id, unsafeByConversion.get(conversion.id).id)
}

assert.equal(runtime.authorityStatus, 'partial', 'this bounded slice must not claim complete runtime authority')
assert(!runtime.compilerObservedModulesWithoutRequirementRoots.includes('HxEnum'),
	'HxEnum should have a semantic requirement root after the enum-to-Dynamic conversion is sealed')
assert(runtime.compilerObservedModulesWithRequirementRoots.includes('HxEnum'),
	'the runtime report should connect generated HxEnum use to a source-level requirement')

const requirements = runtime.requirements.filter(entry =>
	entry.semanticCapability === 'haxe-enum-dynamic-box' && conversionIds.has(entry.decisionId))
assert.equal(requirements.length, enumConversions.length, 'each sealed enum conversion should publish one HxEnum runtime requirement')
for (const requirement of requirements) {
	assert(conversionIds.has(requirement.decisionId), 'the HxEnum requirement should name its exact local conversion')
	assert.deepEqual(requirement.rootModules, ['HxEnum'])
	assert.equal(requirement.subject.id, 'MyEnum')
}

const generatedBoxes = generated.match(/HxEnum\.box_if_needed "MyEnum" \(Obj\.repr/g) || []
assert.equal(generatedBoxes.length, enumConversions.length,
	'OCaml syntax should apply exactly the four sealed enum boxes without adding a second target-side decision')

/**
 * Runs the public inspection command against one output directory.
 *
 * The inspector is the consumer that users and release tooling rely on. Running
 * it here proves the new evidence is not merely well-formed according to this
 * fixture's own assertions.
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

const inspection = inspect('out')
assert.equal(inspection.status, 0, `public inspection rejected the valid enum plan: ${inspection.stdout}${inspection.stderr}`)
const inspectionReport = JSON.parse(inspection.stdout)
assert.equal(inspectionReport.schemaVersion, 31)
assert.equal(inspectionReport.lowering.localConversions.filter(entry => entry.conversion === 'box-exact-enum-to-dynamic').length,
	enumConversions.length)

const tamperRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-enum-dynamic-tamper-'))
const tamperOut = path.join(tamperRoot, 'out')
try {
	/**
	 * Restores the real generated reports before one independent corruption case.
	 *
	 * Each case changes one owner only. This makes a rejection prove the named
	 * contract instead of accidentally depending on damage from a previous case.
	 */
	function resetTamperOutput() {
		fs.rmSync(tamperOut, { recursive: true, force: true })
		fs.cpSync(path.join(fixtureRoot, 'out'), tamperOut, {
			recursive: true,
			filter: source => path.basename(source) !== '_build'
		})
	}

	/** Mutates the copied lowering report and requires the public inspector to reject it. */
	function expectLoweringRejection(label, pattern, mutate) {
		resetTamperOutput()
		const tamperedReportPath = path.join(tamperOut, 'ocaml_lowering_report.json')
		const tamperedReport = JSON.parse(fs.readFileSync(tamperedReportPath, 'utf8'))
		mutate(tamperedReport)
		fs.writeFileSync(tamperedReportPath, JSON.stringify(tamperedReport, null, 2))
		const tamperedInspection = inspect(tamperOut)
		assert.notEqual(tamperedInspection.status, 0, `public inspection accepted ${label}`)
		assert.match(tamperedInspection.stdout + tamperedInspection.stderr, pattern)
	}

	expectLoweringRejection('an enum conversion with a mismatched native carrier', /invalid exact enum-to-Dynamic contract/, report => {
		const conversion = report.localConversions.find(entry => entry.conversion === 'box-exact-enum-to-dynamic')
		conversion.inputCarrierTypeId = 'haxe-enum-native-variant-carrier-v1:OtherEnum'
	})
	expectLoweringRejection('an enum conversion whose source moved while retaining its old ID', /does not match its retained function/, report => {
		const conversion = report.localConversions.find(entry => entry.conversion === 'box-exact-enum-to-dynamic')
		const operation = report.unsafeOperations.find(entry => entry.conversionId === conversion.id)
		conversion.source.min += 1
		conversion.unsafeOperation.source.min += 1
		operation.source.min += 1
	})
	expectLoweringRejection('an enum conversion whose body revision changed while retaining its old ID', /does not match its retained function/, report => {
		const conversion = report.localConversions.find(entry => entry.conversion === 'box-exact-enum-to-dynamic')
		const operation = report.unsafeOperations.find(entry => entry.conversionId === conversion.id)
		conversion.bodyRevision = 'body:coherently-tampered'
		conversion.unsafeOperation.bodyRevision = conversion.bodyRevision
		operation.bodyRevision = conversion.bodyRevision
	})
	expectLoweringRejection('an unsafe record detached from its enum conversion', /does not preserve its sealed enum-to-Dynamic conversion/, report => {
		const operation = report.unsafeOperations.find(entry => entry.operation === 'box-exact-enum-to-dynamic')
		operation.inputSemanticTypeId = 'OtherEnum'
	})
	expectLoweringRejection('an enum conversion without its HxEnum requirement', /refers to missing runtime requirement/, report => {
		const conversion = report.localConversions.find(entry => entry.conversion === 'box-exact-enum-to-dynamic')
		const requirementId = `${conversion.id}:runtime:haxe-enum-dynamic-box`
		report.runtimeRequirements = report.runtimeRequirements.filter(entry => entry.id !== requirementId)
		report.runtimeRequirementCount = report.runtimeRequirements.length
	})
} finally {
	fs.rmSync(tamperRoot, { recursive: true, force: true })
}

console.log('REFLAXE_OCAML_ENUM_DYNAMIC_LOCAL_PLAN:PASS')
