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
const sha256Revision = /^sha256:[0-9a-f]{64}$/
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
	assert.strictEqual(report.schemaVersion, 3)
	assert.strictEqual(report.summary.valid, true)
	assert(report.summary.generatedFileCount > 0)
	assert(report.summary.artifactEntryCount > report.summary.generatedFileCount)
	assert(report.summary.runtimeModuleCount > 0)
	assert.strictEqual(report.summary.loweredPlanCount, 14)
	assert.strictEqual(report.artifactManifest.status, 'present')
	assert.strictEqual(report.artifactManifest.entryCount, report.summary.artifactEntryCount)
	assert.strictEqual(report.artifactManifest.completeForSourceBundle, false)
	assert.strictEqual(report.artifactManifest.blockers.length, 2)
	assert.match(report.artifactManifest.sourceBundleRevision, /^sha256:[0-9a-f]{64}$/)
	assert.match(report.artifactManifest.artifactSetRevision, /^sha256:[0-9a-f]{64}$/)
	assert.strictEqual(report.artifactManifest.semanticRuntime.status, 'incomplete')
	assert.strictEqual(report.artifactManifest.semanticRuntime.model, 'recorded-runtime-requirements-partial-v2')
	assert.match(report.artifactManifest.semanticRuntime.revision, sha256Revision)
	assert.strictEqual(report.artifactManifest.nativeDependencies.status, 'incomplete')
	assert(report.artifactManifest.ownerCounts.some(owner => owner.id === 'reflaxe-framework' && owner.count > 0))
	assert(report.artifactManifest.ownerCounts.some(owner => owner.id === 'runtime-copier' && owner.count > 0))
	assert(report.artifactManifest.ownerCounts.some(owner => owner.id === 'dune-project-emitter' && owner.count > 0))
	const initialSourceBundleRevision = report.artifactManifest.sourceBundleRevision
	const initialArtifactSetRevision = report.artifactManifest.artifactSetRevision
	assert.strictEqual(report.runtime.authority, 'current-compiler-runtime-selection-report')
	assert.strictEqual(report.runtime.semanticManifest, false)
	assert.strictEqual(report.buildTiming.status, 'not-enabled')
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

	const runtimeRequirementPath = path.join(tempRoot, 'out/ocaml_runtime_requirement_report.json')
	const runtimeRequirements = JSON.parse(fs.readFileSync(runtimeRequirementPath, 'utf8'))
	assert.strictEqual(runtimeRequirements.schemaVersion, 2)
	assert.strictEqual(runtimeRequirements.model, 'recorded-ocaml-runtime-requirements')
	assert.strictEqual(runtimeRequirements.authorityStatus, 'partial')
	assert.deepStrictEqual(runtimeRequirements.coveredFamilies, [
		'compiler-core-runtime',
		'compiler-type-registry',
		'typed-place-assignment-and-update'
	])
	assert.strictEqual(runtimeRequirements.selectionAuthority, 'explicit-full-with-recorded-requirement-audit-v2')
	assert.strictEqual(runtimeRequirements.runtimeMode, 'full')
	assert.strictEqual(runtimeRequirements.selectionMode, 'full')
	assert.match(runtimeRequirements.reportRevision, sha256Revision)
	assert.match(runtimeRequirements.requirementRevision, sha256Revision)
	assert.match(runtimeRequirements.runtimeSourceRevision, sha256Revision)
	assert.strictEqual(runtimeRequirements.requirementRevision, report.artifactManifest.semanticRuntime.revision)
	assert.strictEqual(runtimeRequirements.requirementCount, runtimeRequirements.requirements.length)
	assert(runtimeRequirements.requirementCount > 0)
	assert(runtimeRequirements.requirementRootModules.includes('HxInt'))
	assert(runtimeRequirements.requirementClosureModules.includes('HxInt'))
	assert(runtimeRequirements.explainedCompilerObservedModules.includes('HxInt'))
	assert(runtimeRequirements.explainedCompilerObservedModules.includes('HxType'))
	assert.deepStrictEqual(runtimeRequirements.requirementRootsNotCompilerObserved, [])
	assert(runtimeRequirements.unexplainedCompilerObservedModules.length > 0,
		'partial coverage should keep compiler-observed modules from unmigrated families visible')
	const requirementIds = new Set()
	for (const requirement of runtimeRequirements.requirements) {
		assert(!requirementIds.has(requirement.id), `duplicate runtime requirement ${requirement.id}`)
		requirementIds.add(requirement.id)
		assert(requirement.source.file.length > 0)
		assert(!path.isAbsolute(requirement.source.file), `runtime report leaked an absolute source path: ${requirement.source.file}`)
		assert(!/^[A-Za-z]:[\\/]/.test(requirement.source.file), `runtime report leaked a Windows source path: ${requirement.source.file}`)
		assert(!requirement.source.file.split('/').includes('..'), `runtime report leaked parent traversal: ${requirement.source.file}`)
		assert(requirement.source.min >= 0)
		assert(requirement.source.max >= requirement.source.min)
		assert(['haxe-type', 'generated-module', 'compiler-policy', 'native-boundary', 'raw-boundary'].includes(requirement.subject.kind))
		assert(requirement.subject.id.length > 0)
		assert(requirement.rootModules.length > 0)
		assert(requirement.profileEligibility.includes(runtimeRequirements.profile))
	}
	const coreRequirement = runtimeRequirements.requirements.find(requirement => requirement.id === 'compiler:runtime-packaging:core')
	assert(coreRequirement)
	assert.strictEqual(coreRequirement.sourceKind, 'compiler-infrastructure')
	assert.deepStrictEqual(coreRequirement.subject, {kind: 'compiler-policy', id: 'runtime-packaging'})
	assert.deepStrictEqual(coreRequirement.rootModules, ['HxRuntime'])
	const registryRequirement = runtimeRequirements.requirements.find(
		requirement => requirement.id === 'compiler:generated:HxTypeRegistry:type-registry')
	assert(registryRequirement)
	assert.deepStrictEqual(registryRequirement.subject, {kind: 'generated-module', id: 'HxTypeRegistry'})
	assert.deepStrictEqual(registryRequirement.rootModules, ['HxType'])
	assert.strictEqual(runtimeRequirements.requirementChains.length, runtimeRequirements.requirementCount)
	for (const chain of runtimeRequirements.requirementChains) {
		assert(requirementIds.has(chain.requirementId), `runtime chain refers to missing requirement ${chain.requirementId}`)
		assert(chain.resolvedModules.length > 0)
		for (const moduleName of chain.resolvedModules)
			assert(runtimeRequirements.requirementClosureModules.includes(moduleName))
	}
	const runtimeSourcesByModule = new Map(runtimeRequirements.runtimeSources.map(source => [source.module, source]))
	const intRuntimeSource = runtimeSourcesByModule.get('HxInt')
	assert(intRuntimeSource)
	assert.strictEqual(intRuntimeSource.license, 'MIT')
	assert(intRuntimeSource.profiles.includes(runtimeRequirements.profile))
	assert(intRuntimeSource.files.length > 0)
	for (const source of runtimeRequirements.runtimeSources) {
		assert(runtimeRequirements.requirementClosureModules.includes(source.module))
		for (const file of source.files) {
			assert.match(file.sha256, sha256Revision)
			assert(file.bytes > 0)
		}
	}
	for (const id of ['program-representation', 'semantic-runtime-manifest', 'native-dependencies', 'raw-unsafe', 'bindings', 'export-abi']) {
		assert(report.unavailable.some(capability => capability.id === id && capability.status === 'unavailable'))
	}

	const human = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering'])
	assert.strictEqual(human.status, 0, human.stderr || human.stdout)
	assert(human.stdout.includes('reflaxe.ocaml output inspection: VALID'))
	assert(human.stdout.includes('[PASS] Generated artifact ownership:'))
	assert(human.stdout.includes('[BLOCKED] Source-bundle packaging:'))
	assert(human.stdout.includes('explicit requirement coverage is still partial'))
	assert(human.stdout.includes('[SKIP] Native Dune timing'))
	assert(human.stdout.includes('HxRuntime:'))
	assert(human.stdout.includes('assignment/update family only'))
	assert(human.stdout.includes('REFLAXE_OCAML_INSPECT:PASS'))

	const generatedPath = path.join(tempRoot, 'out/_GeneratedFiles.json')
	const generated = JSON.parse(fs.readFileSync(generatedPath, 'utf8'))
	const timingPath = path.join(tempRoot, 'out/ocaml_build_timing_report.json')
	const timing = {
		schemaVersion: 1,
		generatedFilesReceiptId: generated.id,
		mode: 'native',
		duneLayout: 'executable',
		target: './out.exe',
		strict: true,
		requestedRun: false,
		mliMode: 'infer',
		phases: [
			{id: 'native_toolchain_probe', elapsedMilliseconds: 2, exitCode: 0},
			{id: 'mli_toolchain_probe', elapsedMilliseconds: 1, exitCode: 0},
			{id: 'dune_build', elapsedMilliseconds: 12, exitCode: 0},
			{id: 'mli_infer', elapsedMilliseconds: 3, exitCode: 0},
			{id: 'mli_rebuild', elapsedMilliseconds: 4, exitCode: 0}
		],
		boundaries: {
			duneBuildIncludes: ['typecheck', 'compile', 'link'],
			duneCacheHitsMeasured: false,
			loadSeparated: false,
			startupSeparated: false,
			workloadRuntimeSeparated: false
		},
		summary: {
			status: 'passed',
			exitCode: 0,
			nativeBuildRan: true,
			duneBuildMilliseconds: 16,
			interfaceMilliseconds: 4,
			targetRunMilliseconds: null
		}
	}
	fs.writeFileSync(timingPath, JSON.stringify(timing, null, 2) + '\n')
	const timedInspection = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(timedInspection.status, 1)
	const timedReport = JSON.parse(timedInspection.stdout)
	assert.strictEqual(timedReport.buildTiming.duneBuildMilliseconds, 16)
	assert.strictEqual(timedReport.artifactManifest.status, 'invalid')
	assert(timedReport.artifactManifest.message.includes('unregistered non-cache file'))
	const timedHuman = runCli(['inspect', '--project', tempRoot, '--output', 'out'])
	assert.strictEqual(timedHuman.status, 1)
	assert(timedHuman.stdout.includes('16ms for typecheck + compile + link combined'))
	timing.generatedFilesReceiptId += 1
	fs.writeFileSync(timingPath, JSON.stringify(timing, null, 2) + '\n')
	const staleTiming = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(staleTiming.status, 1)
	assert(JSON.parse(staleTiming.stdout).buildTiming.message.includes('current receipt'))
	fs.rmSync(timingPath)
	fs.mkdirSync(timingPath)
	const timingDirectory = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(timingDirectory.status, 1)
	assert(JSON.parse(timingDirectory.stdout).buildTiming.message.includes('found a directory'))
	fs.rmdirSync(timingPath)

	const loweringPath = path.join(tempRoot, 'out/ocaml_lowering_report.json')
	const loweringBytes = fs.readFileSync(loweringPath, 'utf8')
	const lowering = JSON.parse(loweringBytes)
	const removedRequirement = lowering.runtimeRequirements.pop()
	lowering.runtimeRequirementCount -= 1
	fs.writeFileSync(loweringPath, JSON.stringify(lowering, null, 2) + '\n')
	const missingRequirement = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(missingRequirement.status, 1)
	const missingRequirementReport = JSON.parse(missingRequirement.stdout)
	assert.strictEqual(missingRequirementReport.lowering.status, 'invalid')
	assert(missingRequirementReport.lowering.message.includes(`refers to missing runtime requirement "${removedRequirement.id}"`))
	fs.writeFileSync(loweringPath, loweringBytes)
	fs.rmSync(loweringPath)
	const optionalLowering = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(optionalLowering.status, 1)
	const optionalLoweringReport = JSON.parse(optionalLowering.stdout)
	assert.strictEqual(optionalLoweringReport.lowering.status, 'not-enabled')
	assert.strictEqual(optionalLoweringReport.artifactManifest.status, 'invalid')
	assert(optionalLoweringReport.artifactManifest.message.includes('is missing'))
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
	assert.strictEqual(JSON.parse(missing.stdout).summary.errorCount, 4)

	const badOption = runCli(['inspect', '--unknown'])
	assert.strictEqual(badOption.status, 2)
	assert(badOption.stderr.includes('Unknown inspect option'))

	const currentGenerated = JSON.parse(fs.readFileSync(generatedPath, 'utf8'))
	timing.generatedFilesReceiptId = currentGenerated.id
	fs.writeFileSync(timingPath, JSON.stringify(timing, null, 2) + '\n')
	const rebuiltWithoutTiming = cp.spawnSync('haxe', ['build.hxml'], {
		cwd: tempRoot,
		env: process.env,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
	assert.strictEqual(rebuiltWithoutTiming.status, 0, rebuiltWithoutTiming.stderr || rebuiltWithoutTiming.stdout)
	assert(!fs.existsSync(timingPath), 'a build without timing retained a stale report')
	const rebuiltInspection = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(rebuiltInspection.status, 0, rebuiltInspection.stderr || rebuiltInspection.stdout)
	const rebuiltReport = JSON.parse(rebuiltInspection.stdout)
	assert.strictEqual(rebuiltReport.artifactManifest.sourceBundleRevision, initialSourceBundleRevision)
	assert.strictEqual(rebuiltReport.artifactManifest.artifactSetRevision, initialArtifactSetRevision)

	console.log('REFLAXE_OCAML_INSPECT_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, {recursive: true, force: true})
}
