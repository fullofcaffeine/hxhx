#!/usr/bin/env node
/** Proves inspect reports only compiler-owned artifacts and fails closed on stale data. */
const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const tempParent = path.join(repoRoot, '.tmp')
fs.mkdirSync(tempParent, {recursive: true})
const tempRoot = fs.mkdtempSync(path.join(tempParent, 'reflaxe-ocaml-inspect-'))
const sourceFixture = path.join(repoRoot, 'test/portable/fixtures/place_static_field_assign')
const haxeArgs = [
	'-cp', 'packages/reflaxe.ocaml/src',
	'--macro', 'nullSafety("reflaxe.ocaml")',
	'--run', 'reflaxe.ocaml.tooling.ReflaxeOcamlRun'
]

function runCli(args) {
	return cp.spawnSync('haxe', haxeArgs.concat(args), {
		cwd: repoRoot,
		env: process.env,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
}

try {
	fs.cpSync(path.join(sourceFixture, 'src'), path.join(tempRoot, 'src'), {recursive: true})
	const hxml = fs.readFileSync(path.join(sourceFixture, 'build.hxml'), 'utf8') + '\n-D ocaml_no_build\n'
	fs.writeFileSync(path.join(tempRoot, 'build.hxml'), hxml)
	const compile = cp.spawnSync('haxe', ['build.hxml'], {
		cwd: tempRoot,
		env: process.env,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
	assert.strictEqual(compile.status, 0, compile.stderr || compile.stdout)

	const inspected = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(inspected.status, 0, inspected.stderr || inspected.stdout)
	const report = JSON.parse(inspected.stdout)
	assert.strictEqual(report.schemaVersion, 1)
	assert.strictEqual(report.summary.valid, true)
	assert(report.summary.generatedFileCount > 0)
	assert(report.summary.runtimeModuleCount > 0)
	assert.strictEqual(report.summary.loweredPlanCount, 14)
	assert.strictEqual(report.runtime.authority, 'current-compiler-runtime-selection-report')
	assert.strictEqual(report.runtime.semanticManifest, false)
	assert(report.runtime.inclusionReasons.some(reason => reason.module === 'HxRuntime'))
	assert.strictEqual(report.lowering.scope, 'typed-place-assignment-and-update-family')
	assert(report.lowering.message.includes('not a whole-program IR'))
	const update = report.lowering.plans.find(plan => plan.nodeKind === 'static-int-update')
	assert(update)
	assert.strictEqual(update.semanticTypeId, 'Int')
	assert.strictEqual(update.carrierTypeId, 'int')
	assert.strictEqual(update.sourceOffsetUnit, 'byte-offset')
	assert(update.representationReason.includes('OCaml int ref cell'))
	assert.deepStrictEqual(update.schedule, ['load', 'operator', 'store', 'result'])
	assert(update.runtimeRequirementIds.some(id => id.includes('haxe-int32-add')))
	for (const id of ['program-representation', 'semantic-runtime-manifest', 'native-dependencies', 'raw-unsafe', 'bindings', 'export-abi']) {
		assert(report.unavailable.some(capability => capability.id === id && capability.status === 'unavailable'))
	}

	const human = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering'])
	assert.strictEqual(human.status, 0, human.stderr || human.stdout)
	assert(human.stdout.includes('reflaxe.ocaml output inspection: VALID'))
	assert(human.stdout.includes('current report, not semantic manifest'))
	assert(human.stdout.includes('HxRuntime:'))
	assert(human.stdout.includes('assignment/update family only'))
	assert(human.stdout.includes('REFLAXE_OCAML_INSPECT:PASS'))

	const loweringPath = path.join(tempRoot, 'out/ocaml_lowering_report.json')
	fs.rmSync(loweringPath)
	const optionalLowering = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(optionalLowering.status, 0, optionalLowering.stderr || optionalLowering.stdout)
	assert.strictEqual(JSON.parse(optionalLowering.stdout).lowering.status, 'not-enabled')
	const requiredLowering = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering'])
	assert.strictEqual(requiredLowering.status, 1)
	assert(requiredLowering.stdout.includes('[FAIL] Typed place lowering'))
	assert(requiredLowering.stdout.includes('required by --require-lowering'))
	assert(requiredLowering.stdout.includes('REFLAXE_OCAML_INSPECT:FAIL'))

	const profilePath = path.join(tempRoot, 'out/ocaml_profile_report.json')
	const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'))
	profile.normalizedProfile = profile.normalizedProfile === 'portable' ? 'metal' : 'portable'
	fs.writeFileSync(profilePath, JSON.stringify(profile, null, 2) + '\n')
	const inconsistent = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(inconsistent.status, 1)
	assert(JSON.parse(inconsistent.stdout).consistencyErrors.some(message => message.includes('Profile report says')))
	profile.normalizedProfile = report.profile.profile
	fs.writeFileSync(profilePath, JSON.stringify(profile, null, 2) + '\n')

	const generatedPath = path.join(tempRoot, 'out/_GeneratedFiles.json')
	const generated = JSON.parse(fs.readFileSync(generatedPath, 'utf8'))
	generated.filesGenerated.push('../escape.ml')
	fs.writeFileSync(generatedPath, JSON.stringify(generated, null, 2) + '\n')
	const unsafeGenerated = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(unsafeGenerated.status, 1)
	assert(JSON.parse(unsafeGenerated.stdout).generatedFiles.message.includes('unsafe relative path'))
	generated.filesGenerated.pop()
	fs.writeFileSync(generatedPath, JSON.stringify(generated, null, 2) + '\n')

	const runtimePath = path.join(tempRoot, 'out/ocaml_runtime_plan_report.json')
	const runtime = JSON.parse(fs.readFileSync(runtimePath, 'utf8'))
	runtime.selectedModules.push('MissingRuntime')
	runtime.inclusionReasons.push({module: 'MissingRuntime', reasons: ['fixture']})
	fs.writeFileSync(runtimePath, JSON.stringify(runtime, null, 2) + '\n')
	const missingRuntimeSource = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(missingRuntimeSource.status, 1)
	assert(JSON.parse(missingRuntimeSource.stdout).runtime.message.includes('no copied .ml or .mli'))
	runtime.selectedModules.pop()
	runtime.inclusionReasons.pop()
	runtime.schemaVersion = 999
	fs.writeFileSync(runtimePath, JSON.stringify(runtime, null, 2) + '\n')
	const staleRuntime = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(staleRuntime.status, 1)
	const staleReport = JSON.parse(staleRuntime.stdout)
	assert.strictEqual(staleReport.runtime.status, 'invalid')
	assert(staleReport.runtime.message.includes('expected 2'))

	const missing = runCli(['inspect', '--project', tempRoot, '--output', 'missing', '--json'])
	assert.strictEqual(missing.status, 1)
	assert.strictEqual(JSON.parse(missing.stdout).summary.errorCount, 3)

	const badOption = runCli(['inspect', '--unknown'])
	assert.strictEqual(badOption.status, 2)
	assert(badOption.stderr.includes('Unknown inspect option'))

	console.log('REFLAXE_OCAML_INSPECT_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, {recursive: true, force: true})
}
