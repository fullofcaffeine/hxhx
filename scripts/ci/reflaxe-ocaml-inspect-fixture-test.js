#!/usr/bin/env node
/** Proves inspect reports only compiler-owned artifacts and fails closed on stale data. */
const assert = require('assert')
const cp = require('child_process')
const crypto = require('crypto')
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
	assert.strictEqual(report.schemaVersion, 40)
	assert.strictEqual(report.summary.valid, true)
	assert(report.summary.generatedFileCount > 0)
	assert(report.summary.artifactEntryCount > report.summary.generatedFileCount)
	assert(report.summary.runtimeModuleCount > 0)
	assert.strictEqual(report.summary.loweredPlanCount, 21)
	assert(report.summary.representationDecisionCount > 0)
	assert.strictEqual(report.summary.representedArrayCount, report.representation.representedArrays.length)
	assert.strictEqual(report.summary.arrayLiteralProducerCount, report.lowering.arrayLiteralProducers.length)
	assert.strictEqual(report.lowering.arrayLiteralProducerModel, 'ocaml-represented-array-literal-producer-v2')
	assert.match(report.lowering.arrayLiteralProducerRevision, sha256Revision)
	assert(report.summary.staticStorageCount > 0)
	assert.strictEqual(report.artifactManifest.status, 'present')
	assert.strictEqual(report.artifactManifest.entryCount, report.summary.artifactEntryCount)
	assert.strictEqual(report.artifactManifest.completeForSourceBundle, true)
	assert.strictEqual(report.artifactManifest.blockers.length, 0)
	assert.match(report.artifactManifest.sourceBundleRevision, /^sha256:[0-9a-f]{64}$/)
	assert.match(report.artifactManifest.artifactSetRevision, /^sha256:[0-9a-f]{64}$/)
	assert.strictEqual(report.artifactManifest.semanticRuntime.status, 'complete')
	assert.strictEqual(report.artifactManifest.semanticRuntime.model, 'checked-runtime-source-selection-v1')
	assert.match(report.artifactManifest.semanticRuntime.revision, sha256Revision)
	assert.strictEqual(report.artifactManifest.nativeDependencies.status, 'complete')
	assert.strictEqual(report.artifactManifest.nativeDependencies.model, 'normalized-native-source-declarations-v1')
	assert(report.artifactManifest.ownerCounts.some(owner => owner.id === 'reflaxe-framework' && owner.count > 0))
	assert(report.artifactManifest.ownerCounts.some(owner => owner.id === 'runtime-copier' && owner.count > 0))
	assert(report.artifactManifest.ownerCounts.some(owner => owner.id === 'dune-project-emitter' && owner.count > 0))
	const initialSourceBundleRevision = report.artifactManifest.sourceBundleRevision
	const initialArtifactSetRevision = report.artifactManifest.artifactSetRevision
	assert.strictEqual(report.runtime.authority, 'current-compiler-runtime-selection-report')
	assert.strictEqual(report.runtime.semanticManifest, false)
	assert.strictEqual(report.buildTiming.status, 'not-enabled')
	assert(report.runtime.inclusionReasons.some(reason => reason.module === 'HxRuntime'))
	assert.strictEqual(report.lowering.scope, 'typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families')
	assert(report.lowering.message.includes('not a whole-program IR'))
	assert.strictEqual(report.lowering.localConversions.length, report.summary.localConversionCount)
	assert.strictEqual(report.lowering.unsafeOperations.length, report.summary.unsafeOperationCount)
	assert.strictEqual(report.lowering.unsafeOperationCompleteness, 'exact-null-int-null-bool-inline-dynamic-and-enum-to-dynamic-local-and-container-slices')
	assert.match(report.lowering.localConversionRevision, sha256Revision)
	assert.match(report.lowering.unsafeOperationRevision, sha256Revision)
	assert(report.lowering.localConversions.length > 0)
	assert(report.lowering.unsafeOperations.every(operation =>
		report.lowering.localConversions.some(conversion =>
			conversion.id === operation.conversionId && conversion.unsafeOperationId === operation.id)))
	assert.strictEqual(report.lowering.calls.length, report.summary.callCount)
	assert.strictEqual(report.lowering.callableBoundaries.length, report.summary.callableBoundaryCount)
	assert.strictEqual(report.lowering.functionResultBoundaries.length, report.summary.functionResultBoundaryCount)
	assert.match(report.lowering.functionResultBoundaryRevision, sha256Revision)
	assert(report.lowering.functionResultBoundaries.length > 0)
	assert.strictEqual(report.lowering.controls.length, report.summary.controlCount)
	assert.strictEqual(report.lowering.controlTargets.length, report.summary.controlTargetCount)
	assert.strictEqual(report.lowering.controlAdmissions.length, report.summary.controlAdmissionCount)
	assert.match(report.lowering.controlTargetRevision, sha256Revision)
	assert.match(report.lowering.callRevision, sha256Revision)
	assert(report.lowering.calls.every(call =>
		report.lowering.callableBoundaries.some(boundary =>
			boundary.calleeId === call.calleeId
			&& boundary.arguments.length === call.arguments.length
			&& call.arguments.every((argument, index) =>
				boundary.arguments[index].outputRepresentationId === argument.outputRepresentationId)
			&& boundary.result.inputRepresentationId === call.result.inputRepresentationId)))
	assert(report.lowering.calls.some(call =>
		call.arguments.length === 0
		&& call.evaluationSchedule.length === 1
		&& call.evaluationSchedule[0].kind === 'invoke-callee'))
	assert.strictEqual(report.lowering.staticStorage.length, report.summary.staticStorageCount)
	assert.match(report.lowering.staticStorageRevision, sha256Revision)
	assert(report.lowering.staticStorage.some(entry => entry.key === 'Main::Main::sameModuleValue'
		&& entry.declarationSite === 'module-prelude'
		&& entry.carrierTypeId === 'int'))
	assert(report.lowering.staticStorage.some(entry => entry.key === 'Main::Main::sameModuleBool'
		&& entry.declarationSite === 'module-prelude'
		&& entry.carrierTypeId === 'bool'
		&& entry.representationId === 'representation:Bool:static-field'))
	assert(report.lowering.staticStorage.some(entry => entry.key === 'Main::Main::sameModuleNullableInt'
		&& entry.declarationSite === 'module-prelude'
		&& entry.carrierTypeId === 'Obj.t'
		&& entry.representationId === 'representation:Null<Int>:static-field'))
	assert(report.lowering.staticStorage.some(entry => entry.key === 'ExternalHolder::ExternalHolder::omittedNullableBool'
		&& entry.declarationSite === 'owner-binding'
		&& entry.carrierTypeId === 'Obj.t'
		&& entry.representationId === 'representation:Null<Bool>:static-field'))
	assert(report.lowering.staticStorage.some(entry => entry.key === 'Main::Main::sameModuleObject'
		&& entry.declarationSite === 'type-prelude'
		&& entry.carrierTypeId === 'samemoduleworker_t'))
	assert.strictEqual(report.representation.status, 'present')
	assert.strictEqual(report.representation.scope, 'exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15')
	assert.strictEqual(report.representation.decisions.length, report.summary.representationDecisionCount)
	assert(report.representation.representedArrays.some(descriptor => descriptor.id === 'represented-array:Array<Int>'
		&& descriptor.elementRepresentationId === 'representation:Int:array-element'
		&& descriptor.arrayCarrierTypeId === 'int HxArray.t'))
	assert(report.representation.decisions.some(decision => decision.id === 'representation:Int:static-field'
		&& decision.carrierTypeId === 'int'
		&& decision.nullPolicy === 'non-null'
		&& decision.boxingPolicy === 'direct-unboxed'
		&& decision.implicitDefaultPolicy === 'exact-int-zero'))
	assert(report.representation.decisions.some(decision => decision.id === 'representation:Bool:static-field'
		&& decision.carrierTypeId === 'bool'
		&& decision.nullPolicy === 'non-null'
		&& decision.boxingPolicy === 'direct-unboxed'
		&& decision.implicitDefaultPolicy === 'exact-bool-false'))
	assert(report.representation.decisions.some(decision => decision.id === 'representation:Null<Int>:static-field'
		&& decision.carrierTypeId === 'Obj.t'
		&& decision.nullPolicy === 'runtime-sentinel'
		&& decision.boxingPolicy === 'nullable-primitive-carrier'
		&& decision.implicitDefaultPolicy === 'runtime-null-sentinel'))
	assert(report.representation.decisions.some(decision => decision.id === 'representation:Null<Bool>:static-field'
		&& decision.carrierTypeId === 'Obj.t'
		&& decision.nullPolicy === 'runtime-sentinel'
		&& decision.boxingPolicy === 'nullable-primitive-carrier'
		&& decision.implicitDefaultPolicy === 'runtime-null-sentinel'))
	assert(report.representation.decisions.some(decision => decision.id === 'representation:String:static-field'
		&& decision.carrierTypeId === 'string'
		&& decision.nullPolicy === 'runtime-sentinel'
		&& decision.boxingPolicy === 'nullable-string-carrier'
		&& decision.implicitDefaultPolicy === 'runtime-null-sentinel'
		&& decision.proofId === 'nullable-string-runtime-sentinel-carrier-v1'))
	assert(report.lowering.plans.some(plan => plan.nodeKind === 'static-simple-assignment'
		&& plan.semanticTypeId === 'Bool'
		&& plan.carrierTypeId === 'bool'
		&& plan.representationId === 'representation:Bool:static-field'))
	const update = report.lowering.plans.find(plan => plan.nodeKind === 'static-int-update')
	assert(update)
	assert.strictEqual(update.semanticTypeId, 'Int')
	assert.strictEqual(update.carrierTypeId, 'int')
	assert.strictEqual(update.sourceOffsetUnit, 'byte-offset')
	assert(update.representationReason.includes("static field's OCaml ref cell"))
	assert.deepStrictEqual(update.schedule, ['load', 'operator', 'store', 'result'])
	assert(update.runtimeRequirementIds.some(id => id.includes('haxe-int32-add')))

	const runtimeRequirementPath = path.join(tempRoot, 'out/ocaml_runtime_requirement_report.json')
	const runtimeRequirements = JSON.parse(fs.readFileSync(runtimeRequirementPath, 'utf8'))
	assert.strictEqual(runtimeRequirements.schemaVersion, 5)
	assert.strictEqual(runtimeRequirements.model, 'recorded-ocaml-runtime-requirements')
	assert.strictEqual(runtimeRequirements.authorityStatus, 'partial')
	assert.strictEqual(runtimeRequirements.coveredFamilies, undefined)
	assert.deepStrictEqual(runtimeRequirements.recordedSemanticCapabilities, [
		...new Set(runtimeRequirements.requirements.map(requirement => requirement.semanticCapability))
	].sort())
	assert.deepStrictEqual(runtimeRequirements.recordedRequirementSourceKinds, [
		...new Set(runtimeRequirements.requirements.map(requirement => requirement.sourceKind))
	].sort())
	assert.strictEqual(runtimeRequirements.selectionAuthority, 'explicit-full-with-recorded-requirement-audit-v2')
	assert.strictEqual(runtimeRequirements.runtimeMode, 'full')
	assert.strictEqual(runtimeRequirements.selectionMode, 'full')
	assert.match(runtimeRequirements.reportRevision, sha256Revision)
	assert.match(runtimeRequirements.requirementRevision, sha256Revision)
	assert.match(runtimeRequirements.runtimeSourceRevision, sha256Revision)
	assert.notStrictEqual(runtimeRequirements.requirementRevision, report.artifactManifest.semanticRuntime.revision)
	assert.strictEqual(runtimeRequirements.requirementCount, runtimeRequirements.requirements.length)
	assert(runtimeRequirements.requirementCount > 0)
	assert(runtimeRequirements.requirementRootModules.includes('HxInt'))
	assert(runtimeRequirements.requirementClosureModules.includes('HxInt'))
	assert.strictEqual(runtimeRequirements.compilerObservationGranularity, 'module-name-only')
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxInt'))
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxType'))
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxBacktrace'))
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxFPHelper'))
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxString'))
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxBytes'))
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxEnum'))
	assert.strictEqual(runtimeRequirements.explainedCompilerObservedModules, undefined)
	assert.strictEqual(runtimeRequirements.unexplainedCompilerObservedModules, undefined)
	assert.deepStrictEqual([
		...runtimeRequirements.compilerObservedModulesWithRequirementRoots,
		...runtimeRequirements.compilerObservedModulesWithoutRequirementRoots
	].sort(), runtimeRequirements.compilerObservedModules)
	assert.deepStrictEqual(runtimeRequirements.requirementRootsNotCompilerObserved, [])
	assert(runtimeRequirements.compilerObservedModulesWithRequirementRoots.includes('HxAnon'))
	assert.deepStrictEqual(runtimeRequirements.compilerObservedModulesWithoutRequirementRoots, [])
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
	const bytesProducerRequirement = runtimeRequirements.requirements.find(requirement => requirement.semanticCapability === 'haxe-bytes-producer')
	assert(bytesProducerRequirement)
	assert.strictEqual(bytesProducerRequirement.sourceKind, 'haxe-expression')
	assert.deepStrictEqual(bytesProducerRequirement.subject, {kind: 'haxe-type', id: 'haxe.io.Bytes'})
	assert.deepStrictEqual(bytesProducerRequirement.rootModules, ['HxBytes'])
	assert.deepStrictEqual(coreRequirement.rootModules, ['HxRuntime'])
	const registryRequirement = runtimeRequirements.requirements.find(
		requirement => requirement.id === 'compiler:generated:HxTypeRegistry:type-registry')
	assert(registryRequirement)
	assert.deepStrictEqual(registryRequirement.subject, {kind: 'generated-module', id: 'HxTypeRegistry'})
	assert.deepStrictEqual(registryRequirement.rootModules, ['HxType'])
	const stringRequirement = runtimeRequirements.requirements.find(
		requirement => requirement.semanticCapability === 'haxe-string-null-sentinel')
	assert(stringRequirement)
	assert.strictEqual(stringRequirement.sourceKind, 'representation-decision')
	assert.strictEqual(stringRequirement.cause, 'representation-decision')
	assert.deepStrictEqual(stringRequirement.subject, {kind: 'haxe-type', id: 'String'})
	assert.deepStrictEqual(stringRequirement.rootModules, ['HxString'])
	const stdioRequirement = runtimeRequirements.requirements.find(
		requirement => requirement.semanticCapability === 'haxe-standard-io')
	assert(stdioRequirement)
	assert.strictEqual(stdioRequirement.sourceKind, 'native-boundary')
	assert.strictEqual(stdioRequirement.cause, 'native-boundary')
	assert.strictEqual(stdioRequirement.subject.kind, 'native-boundary')
	assert.strictEqual(stdioRequirement.subject.id, 'sys.io.Stdio::sys.io._Stdio.NativeHxStdio.flush -> HxStdio.flush')
	assert.deepStrictEqual(stdioRequirement.rootModules, ['HxStdio'])
	const stackRequirement = runtimeRequirements.requirements.find(
		requirement => requirement.semanticCapability === 'haxe-stack-traces')
	assert(stackRequirement)
	assert.strictEqual(stackRequirement.sourceKind, 'native-boundary')
	assert.strictEqual(stackRequirement.cause, 'native-boundary')
	assert.strictEqual(stackRequirement.subject.kind, 'native-boundary')
	assert.strictEqual(stackRequirement.subject.id,
		'haxe.CallStack::haxe._CallStack.NativeHxBacktrace.callstack_lines -> HxBacktrace.callstack_lines')
	assert.deepStrictEqual(stackRequirement.rootModules, ['HxBacktrace'])
	assert.deepStrictEqual(runtimeRequirements.requirements
		.filter(requirement => requirement.semanticCapability === 'haxe-stack-traces')
		.map(requirement => requirement.id)
		.sort(), [
			'native:haxe.CallStack::haxe._CallStack.NativeHxBacktrace.callstack_lines:runtime:haxe-stack-traces',
			'native:haxe.CallStack::haxe._CallStack.NativeHxBacktrace.exceptionstack_lines:runtime:haxe-stack-traces',
			'native:haxe.NativeStackTrace::haxe._NativeStackTrace.NativeHxBacktrace.callstack_lines:runtime:haxe-stack-traces',
			'native:haxe.NativeStackTrace::haxe._NativeStackTrace.NativeHxBacktrace.exceptionstack_lines:runtime:haxe-stack-traces'
		])
	const floatBitsRequirement = runtimeRequirements.requirements.find(
		requirement => requirement.semanticCapability === 'haxe-float-bit-conversions')
	assert(floatBitsRequirement)
	assert.strictEqual(floatBitsRequirement.sourceKind, 'native-boundary')
	assert.strictEqual(floatBitsRequirement.cause, 'native-boundary')
	assert.strictEqual(floatBitsRequirement.subject.kind, 'native-boundary')
	assert.strictEqual(floatBitsRequirement.subject.id,
		'haxe.io.FPHelper::haxe.io._FPHelper.NativeFPHelper.doubleToI64Parts -> HxFPHelper.doubleToI64Parts')
	assert.deepStrictEqual(floatBitsRequirement.rootModules, ['HxFPHelper'])
	assert.deepStrictEqual(runtimeRequirements.requirements
		.filter(requirement => requirement.semanticCapability === 'haxe-float-bit-conversions')
		.map(requirement => requirement.id)
		.sort(), [
			'native:haxe.io.FPHelper::haxe.io._FPHelper.NativeFPHelper.doubleToI64Parts:runtime:haxe-float-bit-conversions',
			'native:haxe.io.FPHelper::haxe.io._FPHelper.NativeFPHelper.floatToI32:runtime:haxe-float-bit-conversions',
			'native:haxe.io.FPHelper::haxe.io._FPHelper.NativeFPHelper.i32ToFloat:runtime:haxe-float-bit-conversions',
			'native:haxe.io.FPHelper::haxe.io._FPHelper.NativeFPHelper.i64ToDouble:runtime:haxe-float-bit-conversions'
		])
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
	for (const id of ['semantic-runtime-manifest', 'native-dependencies', 'bindings', 'export-abi']) {
		assert(report.unavailable.some(capability => capability.id === id && capability.status === 'unavailable'))
	}
	assert(report.unavailable.some(capability => capability.id === 'raw-unsafe' && capability.status === 'partial'))
	assert(!report.unavailable.some(capability => capability.id === 'program-representation'))

	const human = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering'])
	assert.strictEqual(human.status, 0, human.stderr || human.stdout)
	assert(human.stdout.includes('reflaxe.ocaml output inspection: VALID'))
	assert(human.stdout.includes('[PASS] Generated artifact ownership:'))
	assert(human.stdout.includes('source bundle is complete'))
	assert(!human.stdout.includes('[BLOCKED] Source-bundle packaging:'))
	assert(human.stdout.includes('explicit requirement coverage is still partial'))
	assert(human.stdout.includes('[SKIP] Native Dune timing'))
	assert(human.stdout.includes('HxRuntime:'))
	assert(human.stdout.includes('assignment/update family only'))
	assert(human.stdout.includes('[PASS] Program representation registry:'))
	assert(human.stdout.includes('[PASS] Direct represented array literals:'))
	assert(human.stdout.includes('[PASS] Local carrier conversions:'))
	assert(human.stdout.includes('[PARTIAL] Unsafe carrier proof ledger:'))
	assert(human.stdout.includes('[PASS] Function results:'))
	assert(human.stdout.includes('[PASS] Mutable static storage:'))
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
	const staleArrayDescriptorValue = JSON.parse(loweringBytes)
	const staleArrayDescriptor = staleArrayDescriptorValue.representedArrays.find(
		descriptor => descriptor.id === 'represented-array:Array<Int>')
	assert(staleArrayDescriptor)
	staleArrayDescriptor.elementRepresentationRevision = 'sha256:' + '0'.repeat(64)
	staleArrayDescriptorValue.representedArrayRevision = 'sha256:' + crypto.createHash('sha256')
		.update(JSON.stringify(staleArrayDescriptorValue.representedArrays)).digest('hex')
	fs.writeFileSync(loweringPath, JSON.stringify(staleArrayDescriptorValue, null, 2) + '\n')
	const staleArrayDescriptorResult = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(staleArrayDescriptorResult.status, 1)
	const staleArrayDescriptorReport = JSON.parse(staleArrayDescriptorResult.stdout)
	assert.strictEqual(staleArrayDescriptorReport.representation.status, 'invalid')
	assert(staleArrayDescriptorReport.representation.message.includes('does not match its exact array-element representation'))
	fs.writeFileSync(loweringPath, loweringBytes)
	const staleRepresentationLeafValue = JSON.parse(loweringBytes)
	const staleRepresentationLeaf = staleRepresentationLeafValue.representations.find(
		representation => representation.id === 'representation:Array<Int>:internal-value')
	assert(staleRepresentationLeaf)
	staleRepresentationLeaf.reason += ' corrupted'
	staleRepresentationLeafValue.representationRevision = 'sha256:' + crypto.createHash('sha256')
		.update(JSON.stringify(staleRepresentationLeafValue.representations)).digest('hex')
	fs.writeFileSync(loweringPath, JSON.stringify(staleRepresentationLeafValue, null, 2) + '\n')
	const staleRepresentationLeafResult = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(staleRepresentationLeafResult.status, 1)
	const staleRepresentationLeafReport = JSON.parse(staleRepresentationLeafResult.stdout)
	assert.strictEqual(staleRepresentationLeafReport.representation.status, 'invalid')
	assert(staleRepresentationLeafReport.representation.message.includes('revision does not match its reported leaf facts'))
	fs.writeFileSync(loweringPath, loweringBytes)
	const corruptStringRequirementValue = JSON.parse(loweringBytes)
	const corruptStringRequirement = corruptStringRequirementValue.runtimeRequirements.find(
		requirement => requirement.semanticCapability === 'haxe-string-null-sentinel')
	assert(corruptStringRequirement)
	corruptStringRequirement.rootModules = ['HxInt']
	fs.writeFileSync(loweringPath, JSON.stringify(corruptStringRequirementValue, null, 2) + '\n')
	const corruptStringRequirementResult = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(corruptStringRequirementResult.status, 1)
	const corruptStringRequirementReport = JSON.parse(corruptStringRequirementResult.stdout)
	assert.strictEqual(corruptStringRequirementReport.lowering.status, 'invalid')
	assert(corruptStringRequirementReport.lowering.message.includes('does not match the sealed exact String dependency'))
	fs.writeFileSync(loweringPath, loweringBytes)
	const missingUnsafeValue = JSON.parse(loweringBytes)
	const removedUnsafe = missingUnsafeValue.unsafeOperations.pop()
	if (removedUnsafe) {
		missingUnsafeValue.unsafeOperationCount -= 1
		fs.writeFileSync(loweringPath, JSON.stringify(missingUnsafeValue, null, 2) + '\n')
		const missingUnsafe = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
		assert.strictEqual(missingUnsafe.status, 1)
		const missingUnsafeReport = JSON.parse(missingUnsafe.stdout)
		assert.strictEqual(missingUnsafeReport.lowering.status, 'invalid')
		assert(missingUnsafeReport.lowering.message.includes('refers to a missing unsafe operation'))
		fs.writeFileSync(loweringPath, loweringBytes)
	}
	const missingRepresentationValue = JSON.parse(loweringBytes)
	const referencedRepresentationId = missingRepresentationValue.plans[0].place.representationId
	const removedRepresentationIndex = missingRepresentationValue.representations.findIndex(
		representation => representation.id === referencedRepresentationId)
	assert(removedRepresentationIndex >= 0)
	const [removedRepresentation] = missingRepresentationValue.representations.splice(removedRepresentationIndex, 1)
	missingRepresentationValue.representationCount -= 1
	missingRepresentationValue.representationRevision = 'sha256:' + crypto.createHash('sha256')
		.update(JSON.stringify(missingRepresentationValue.representations)).digest('hex')
	fs.writeFileSync(loweringPath, JSON.stringify(missingRepresentationValue, null, 2) + '\n')
	const missingRepresentation = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(missingRepresentation.status, 1)
	const missingRepresentationReport = JSON.parse(missingRepresentation.stdout)
	assert.strictEqual(missingRepresentationReport.representation.status, 'invalid')
	assert(missingRepresentationReport.representation.message.includes(`missing program representation`)
		|| missingRepresentationReport.representation.message.includes(removedRepresentation.id))
	fs.writeFileSync(loweringPath, loweringBytes)
	const wrongDomainValue = JSON.parse(loweringBytes)
	const staticRepresentation = wrongDomainValue.representations.find(
		representation => representation.id === 'representation:Int:static-field')
	assert(staticRepresentation)
	staticRepresentation.domain = 'array-element'
	wrongDomainValue.representationRevision = 'sha256:' + crypto.createHash('sha256')
		.update(JSON.stringify(wrongDomainValue.representations)).digest('hex')
	fs.writeFileSync(loweringPath, JSON.stringify(wrongDomainValue, null, 2) + '\n')
	const wrongDomain = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(wrongDomain.status, 1)
	const wrongDomainReport = JSON.parse(wrongDomain.stdout)
	assert.strictEqual(wrongDomainReport.representation.status, 'invalid')
	assert(wrongDomainReport.representation.message.includes('revision does not match its reported leaf facts'))
	fs.writeFileSync(loweringPath, loweringBytes)
	const missingMutationPolicyValue = JSON.parse(loweringBytes)
	delete missingMutationPolicyValue.representations[0].storageMutationPolicy
	missingMutationPolicyValue.representationRevision = 'sha256:' + crypto.createHash('sha256')
		.update(JSON.stringify(missingMutationPolicyValue.representations)).digest('hex')
	fs.writeFileSync(loweringPath, JSON.stringify(missingMutationPolicyValue, null, 2) + '\n')
	const missingMutationPolicy = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(missingMutationPolicy.status, 1)
	const missingMutationPolicyReport = JSON.parse(missingMutationPolicy.stdout)
	assert.strictEqual(missingMutationPolicyReport.representation.status, 'invalid')
	assert(missingMutationPolicyReport.representation.message.includes('storageMutationPolicy'))
	fs.writeFileSync(loweringPath, loweringBytes)
	const wrongStaticCountValue = JSON.parse(loweringBytes)
	wrongStaticCountValue.staticStorageCount += 1
	fs.writeFileSync(loweringPath, JSON.stringify(wrongStaticCountValue, null, 2) + '\n')
	const wrongStaticCount = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(wrongStaticCount.status, 1)
	const wrongStaticCountReport = JSON.parse(wrongStaticCount.stdout)
	assert.strictEqual(wrongStaticCountReport.lowering.status, 'invalid')
	assert(wrongStaticCountReport.lowering.message.includes('staticStorageCount'))
	fs.writeFileSync(loweringPath, loweringBytes)
	fs.rmSync(loweringPath)
	const optionalLowering = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(optionalLowering.status, 1)
	const optionalLoweringReport = JSON.parse(optionalLowering.stdout)
	assert.strictEqual(optionalLoweringReport.lowering.status, 'not-enabled')
	assert.strictEqual(optionalLoweringReport.representation.status, 'not-enabled')
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
	profile.schemaVersion = 999
	fs.writeFileSync(profilePath, JSON.stringify(profile, null, 2) + '\n')
	const staleProfile = runCli(['inspect', '--project', tempRoot, '--output', 'out', '--json'])
	assert.strictEqual(staleProfile.status, 1)
	const staleProfileReport = JSON.parse(staleProfile.stdout)
	assert.strictEqual(staleProfileReport.profile.status, 'invalid')
	assert(staleProfileReport.profile.message.includes('expected 3'))
	profile.schemaVersion = 3
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
