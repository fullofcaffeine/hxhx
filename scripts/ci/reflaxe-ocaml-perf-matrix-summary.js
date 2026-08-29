#!/usr/bin/env node
/**
 * Combines Linux and macOS performance receipts for one immutable package.
 *
 * Absolute timings stay attached to their own host. The aggregate proves that
 * both hosts measured the same installed ZIP with the same method; it does not
 * turn unrelated GitHub runners into a synthetic cross-host speed ranking.
 */
const fs = require('fs')
const path = require('path')

const { loadArtifactManifest, sha256File } = require('../release/reflaxe-ocaml-package-artifact')

const scenarioContract = new Map([
	['ro-perf-01', { kind: 'build_native', buildReps: 3 }],
	['ro-perf-02', { kind: 'build_native', buildReps: 3 }],
	['ro-perf-03', { kind: 'build_native', buildReps: 3 }],
	['ro-perf-04', { kind: 'build_native', buildReps: 3 }],
	['ro-perf-05', { kind: 'runtime_bench', buildReps: 3, runReps: 9 }],
	['ro-perf-06', { kind: 'runtime_bench', buildReps: 3, runReps: 9 }]
])
const iterationStateOrder = ['cold-output', 'warm-unchanged', 'one-file-change']
const iterationMetricFields = {
	fullHaxeChild: 'fullHaxeChildMilliseconds',
	targetSubprocess: 'targetSubprocessMilliseconds',
	outsideTargetSubprocess: 'outsideTargetSubprocessMilliseconds',
	duneBuild: 'duneBuildMilliseconds',
	interface: 'interfaceMilliseconds',
	externalVerification: 'externalVerificationMilliseconds'
}

function fail(message) {
	throw new Error(message)
}

function parseArgs(argv) {
	const values = {}
	for (let index = 0; index < argv.length; index += 2) {
		const key = argv[index]
		const value = argv[index + 1]
		if (!key || !key.startsWith('--') || value == null) {
			fail(`invalid arguments: ${argv.join(' ')}`)
		}
		values[key.slice(2)] = value
	}
	for (const required of ['artifact-manifest', 'evidence-root', 'out']) {
		if (!values[required]) {
			fail(`missing required --${required}`)
		}
	}
	return values
}

function findSummaries(root) {
	const summaries = []
	function visit(directory) {
		for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
			const absolute = path.join(directory, entry.name)
			if (entry.isDirectory()) {
				visit(absolute)
			} else if (entry.isFile() && entry.name === 'summary.json') {
				summaries.push(JSON.parse(fs.readFileSync(absolute, 'utf8')))
			}
		}
	}
	visit(root)
	return summaries
}

function assertNoAbsolutePaths(value, location = 'summary') {
	if (typeof value === 'string') {
		if (path.posix.isAbsolute(value) || path.win32.isAbsolute(value)) {
			fail(`${location} contains a machine-local absolute path`)
		}
		return
	}
	if (Array.isArray(value)) {
		value.forEach((item, index) => assertNoAbsolutePaths(item, `${location}[${index}]`))
		return
	}
	if (value && typeof value === 'object') {
		for (const [key, item] of Object.entries(value)) {
			assertNoAbsolutePaths(item, `${location}.${key}`)
		}
	}
}

function requireFiniteNumber(value, label, minimum = 0) {
	if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum) {
		fail(`${label} must be a finite number >= ${minimum}`)
	}
}

function roundedMedian(values) {
	const sorted = [...values].sort((left, right) => left - right)
	const middle = Math.floor(sorted.length / 2)
	return sorted.length % 2 === 1
		? sorted[middle]
		: Math.round((sorted[middle - 1] + sorted[middle]) / 2)
}

function validateStats(stats, expectedReps, label) {
	if (!stats || !Array.isArray(stats.samplesMs) || stats.samplesMs.length !== expectedReps || stats.reps !== expectedReps) {
		fail(`${label} must retain exactly ${expectedReps} raw samples`)
	}
	stats.samplesMs.forEach((sample, index) => requireFiniteNumber(sample, `${label}.samplesMs[${index}]`, 0))
	for (const field of ['avgMs', 'bestMs', 'medianMs', 'worstMs']) {
		requireFiniteNumber(stats[field], `${label}.${field}`, 0)
	}
	const expected = {
		avgMs: Math.round(stats.samplesMs.reduce((sum, value) => sum + value, 0) / expectedReps),
		bestMs: Math.min(...stats.samplesMs),
		medianMs: roundedMedian(stats.samplesMs),
		worstMs: Math.max(...stats.samplesMs)
	}
	for (const [field, value] of Object.entries(expected)) {
		if (stats[field] !== value) {
			fail(`${label}.${field} does not match its raw samples`)
		}
	}
}

function validateScenario(scenario, platform) {
	const contract = scenarioContract.get(scenario.id)
	if (!contract || scenario.kind !== contract.kind) {
		fail(`${platform} contains an unknown or incorrectly typed scenario ${scenario.id || '(missing)'}`)
	}
	if (scenario.passed !== true || scenario.compileStatus !== 0 || scenario.referenceComparisonsEnforced !== false) {
		fail(`${platform} scenario ${scenario.id} did not pass the platform-report method`)
	}
	if (!scenario.verification || scenario.verification.passed !== true || scenario.verification.stdoutMatches !== true) {
		fail(`${platform} scenario ${scenario.id} did not verify runtime output`)
	}
	for (const field of ['expectedStdoutSha256', 'actualStdoutSha256']) {
		if (!/^[0-9a-f]{64}$/.test(scenario.verification[field] || '')) {
			fail(`${platform} scenario ${scenario.id} has invalid ${field}`)
		}
	}
	if (scenario.verification.expectedStdoutSha256 !== scenario.verification.actualStdoutSha256) {
		fail(`${platform} scenario ${scenario.id} recorded different expected and actual output`)
	}
	if (!scenario.measured) {
		fail(`${platform} scenario ${scenario.id} has no measurements`)
	}
	validateStats(scenario.measured.build, contract.buildReps, `${platform}.${scenario.id}.build`)
	if (!Number.isInteger(scenario.measured.generatedMlFileCount) || scenario.measured.generatedMlFileCount <= 0) {
		fail(`${platform} scenario ${scenario.id} did not record generated OCaml files`)
	}
	for (const field of ['generatedMlBytes', 'executableBytes']) {
		requireFiniteNumber(scenario.measured[field], `${platform}.${scenario.id}.${field}`, 1)
	}
	if (contract.runReps) {
		if (scenario.runStatus !== 0) {
			fail(`${platform} scenario ${scenario.id} native runtime failed`)
		}
		validateStats(scenario.measured.run, contract.runReps, `${platform}.${scenario.id}.run`)
		if (scenario.measured.build.medianMs <= 0 || scenario.measured.run.medianMs <= 0) {
			fail(`${platform} scenario ${scenario.id} must retain positive build and run medians`)
		}
	}
	return {
		id: scenario.id,
		kind: scenario.kind,
		measured: scenario.measured,
		verification: scenario.verification,
		comparisons: scenario.comparisons
	}
}

function validateIterationSamples(samples, expectedCycles, warmup, platform, sourceFile) {
	if (!Array.isArray(samples) || samples.length !== expectedCycles * iterationStateOrder.length) {
		fail(`${platform} iteration receipt must retain ${expectedCycles * iterationStateOrder.length} ${warmup ? 'warmup' : 'measured'} samples`)
	}
	for (const [index, sample] of samples.entries()) {
		const expectedState = iterationStateOrder[index % iterationStateOrder.length]
		const expectedCycle = Math.floor(index / iterationStateOrder.length) + 1
		const expectedOutputState = expectedState === 'cold-output' ? 'removed-before-build' : 'preserved-from-prior-state'
		if (sample.state !== expectedState || sample.outputState !== expectedOutputState
			|| sample.cycle !== expectedCycle || sample.warmup !== warmup) {
			fail(`${platform} iteration sample order or cycle identity changed`)
		}
		if (sample.compileStatus !== 0 || sample.timingReportValidationPassed !== true || sample.verificationStatus !== 0) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} did not pass build, timing validation, and execution`)
		}
		const expectedSourceChanges = expectedState === 'one-file-change' ? [sourceFile] : []
		if (JSON.stringify(sample.sourceFilesChanged) !== JSON.stringify(expectedSourceChanges)) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} changed the wrong Haxe source set`)
		}
		if (!Array.isArray(sample.generatedCodeChangedFiles)
			|| (expectedState === 'warm-unchanged' && sample.generatedCodeChangedFiles.length !== 0)
			|| (expectedState !== 'warm-unchanged' && sample.generatedCodeChangedFiles.length === 0)) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} has an invalid generated-code change inventory`)
		}
		if (!Number.isInteger(sample.generatedCodeFileCount) || sample.generatedCodeFileCount <= 0
			|| !Number.isInteger(sample.generatedFilesReceiptId) || sample.generatedFilesReceiptId < 0) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} has incomplete generated-output identity`)
		}
		for (const field of Object.values(iterationMetricFields)) {
			requireFiniteNumber(sample[field], `${platform}.iteration.${expectedCycle}.${expectedState}.${field}`, 0)
		}
		if (sample.targetRunMilliseconds !== null
			|| JSON.stringify(sample.duneBuildIncludes) !== JSON.stringify(['typecheck', 'compile', 'link'])
			|| sample.duneCacheHitsMeasured !== false || sample.loadSeparated !== false
			|| sample.startupSeparated !== false || sample.workloadRuntimeSeparated !== false) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} overstates an unmeasured timing boundary`)
		}
		if (!Array.isArray(sample.timingPhases) || sample.timingPhases.length === 0) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} has no target phase samples`)
		}
		let targetTotal = 0
		let duneTotal = 0
		let interfaceTotal = 0
		const phaseIds = new Set()
		for (const phase of sample.timingPhases) {
			if (typeof phase.id !== 'string' || phaseIds.has(phase.id) || phase.exitCode !== 0) {
				fail(`${platform} iteration ${expectedCycle}/${expectedState} has an invalid target phase`)
			}
			phaseIds.add(phase.id)
			requireFiniteNumber(phase.elapsedMilliseconds, `${platform}.iteration.${expectedCycle}.${expectedState}.${phase.id}`, 0)
			targetTotal += phase.elapsedMilliseconds
			if (phase.id === 'dune_build' || phase.id === 'mli_rebuild') {
				duneTotal += phase.elapsedMilliseconds
			} else if (phase.id.startsWith('mli_')) {
				interfaceTotal += phase.elapsedMilliseconds
			}
		}
		if (sample.targetSubprocessMilliseconds > sample.fullHaxeChildMilliseconds
			|| sample.targetSubprocessMilliseconds !== targetTotal || sample.duneBuildMilliseconds !== duneTotal
			|| sample.interfaceMilliseconds !== interfaceTotal
			|| sample.outsideTargetSubprocessMilliseconds !== sample.fullHaxeChildMilliseconds - targetTotal) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} summary disagrees with its target phases`)
		}
		for (const field of ['expectedStdoutSha256', 'actualStdoutSha256']) {
			if (!/^[0-9a-f]{64}$/.test(sample[field] || '')) {
				fail(`${platform} iteration ${expectedCycle}/${expectedState} has invalid ${field}`)
			}
		}
		if (sample.expectedStdoutSha256 !== sample.actualStdoutSha256) {
			fail(`${platform} iteration ${expectedCycle}/${expectedState} did not match expected runtime output`)
		}
	}
}

function validateIteration(iteration, platform) {
	if (!iteration || iteration.id !== 'ro-iteration-01' || iteration.kind !== 'authoring_iteration' || iteration.passed !== true
		|| iteration.owner?.measurementBead !== 'haxe_ocaml-850ii.21' || iteration.owner?.workflowBead !== 'haxe_ocaml-1hd2w') {
		fail(`${platform} is missing the owned standalone iteration workload`)
	}
	const method = iteration.method
	if (!method || JSON.stringify(method.stateOrder) !== JSON.stringify(iterationStateOrder)
		|| method.warmupCycles !== 1 || method.measuredCycles !== 3
		|| method.thresholdMode !== 'report-only-until-stable-hosted-trend'
		|| method.outputDirectoryRemovedOnlyBeforeCold !== true || method.sharedToolchainCachesMayRemainWarm !== true
		|| method.cacheHitsInferred !== false || method.trackedSourcesMutated !== false
		|| JSON.stringify(method.fullHaxeChildIncludes) !== JSON.stringify(['startup', 'typing', 'generation', 'orchestration', 'target-owned-subprocesses'])
		|| JSON.stringify(method.duneBuildIncludes) !== JSON.stringify(['typecheck', 'compile', 'link'])
		|| method.loadSeparated !== false || method.startupSeparated !== false || method.workloadRuntimeSeparated !== false) {
		fail(`${platform} standalone iteration method changed or overstates its timing authority`)
	}
	if (iteration.command?.executable !== 'haxe'
		|| JSON.stringify(iteration.command.args) !== JSON.stringify(['build.hxml', '-D', 'ocaml_build=native', '-D', 'ocaml_build_timing_report'])) {
		fail(`${platform} standalone iteration command changed`)
	}
	if (iteration.fixture?.exampleDir !== 'packages/reflaxe.ocaml/examples/build-macro'
		|| iteration.fixture?.sourceFile !== 'src/BuildMacro.hx'
		|| iteration.fixture?.sourceFilesChangedPerOneFileState !== 1 || iteration.fixture?.sourceRestored !== true) {
		fail(`${platform} standalone iteration fixture ownership changed`)
	}
	validateIterationSamples(iteration.warmupSamples, method.warmupCycles, true, platform, iteration.fixture.sourceFile)
	validateIterationSamples(iteration.samples, method.measuredCycles, false, platform, iteration.fixture.sourceFile)
	const allSamples = [...iteration.warmupSamples, ...iteration.samples]
	const beforeHashes = new Set(allSamples.filter(sample => sample.state !== 'one-file-change').map(sample => sample.actualStdoutSha256))
	const changedHashes = new Set(allSamples.filter(sample => sample.state === 'one-file-change').map(sample => sample.actualStdoutSha256))
	if (beforeHashes.size !== 1 || changedHashes.size !== 1 || [...beforeHashes][0] === [...changedHashes][0]) {
		fail(`${platform} standalone iteration did not prove stable before/after executable behavior`)
	}
	for (const [measurementKey, sampleState] of [['cold', 'cold-output'], ['warm', 'warm-unchanged'], ['oneFile', 'one-file-change']]) {
		const selected = iteration.samples.filter(sample => sample.state === sampleState)
		for (const [metricKey, sampleField] of Object.entries(iterationMetricFields)) {
			const measurement = iteration.measurements?.[measurementKey]?.[metricKey]
			validateStats(measurement, method.measuredCycles, `${platform}.iteration.${measurementKey}.${metricKey}`)
			if (JSON.stringify(measurement.samplesMs) !== JSON.stringify(selected.map(sample => sample[sampleField]))) {
				fail(`${platform} iteration ${measurementKey}.${metricKey} does not summarize its ordered raw samples`)
			}
		}
	}
	return iteration
}

function validateConsumer(summary, manifest, manifestSha256) {
	assertNoAbsolutePaths(summary)
	const platform = summary.environment && summary.environment.platform
	if (summary.schemaVersion !== 2 || summary.marker !== 'RO_TARGET_PERF_PLATFORM:PASS' || summary.mode !== 'platform-report') {
		fail(`performance receipt on ${platform || '(unknown)'} did not pass`)
	}
	if (!summary.method
		|| summary.method.id !== 'installed-package-platform-v2'
		|| summary.method.rawSamplesRetained !== true
		|| summary.method.sampleOrderPreserved !== true
		|| summary.method.outputDirectoryRemovedBeforeEachBuild !== true
		|| summary.method.sharedToolchainCachesMayRemainWarm !== true
		|| summary.method.runtimeVerificationExcludedFromBuildTiming !== true
		|| JSON.stringify(summary.method.iterationStateOrder) !== JSON.stringify(iterationStateOrder)
		|| summary.method.iterationWarmupCycles !== 1
		|| summary.method.iterationMeasuredCycles !== 3
		|| summary.method.iterationThresholdMode !== 'report-only-until-stable-hosted-trend'
		|| summary.method.crossHostAbsoluteComparisonAllowed !== false
		|| summary.method.referenceThresholdsEnforced !== false) {
		fail(`performance receipt on ${platform} used a different measurement method`)
	}
	if (!summary.evidence || summary.evidence.machineLocalPathsRedacted !== true) {
		fail(`performance receipt on ${platform} did not sanitize its evidence`)
	}
	if (!summary.environment || !summary.environment.cpu || !Number.isInteger(summary.environment.cpu.count)
		|| summary.environment.cpu.count <= 0 || typeof summary.environment.cpu.model !== 'string') {
		fail(`performance receipt on ${platform} has incomplete host metadata`)
	}
	const provenance = summary.provenance
	if (!provenance || provenance.implementationCommit !== manifest.implementationCommit
		|| provenance.workingTreeDirty !== false || provenance.installedPackageProof !== true
		|| provenance.artifactManifestSha256 !== manifestSha256) {
		fail(`performance receipt on ${platform} is not tied to the clean package commit`)
	}
	for (const field of ['name', 'version', 'archiveFile', 'sha256', 'bytes', 'sourceOnly', 'fileCount', 'reproducible']) {
		if (!provenance.package || provenance.package[field] !== manifest.package[field]) {
			fail(`performance receipt on ${platform} disagrees on package ${field}`)
		}
	}
	const installation = provenance.installation
	if (!installation || installation.buildMode !== 'supplied'
		|| installation.targetResolvedOutsideCheckout !== true
		|| installation.isolationSmokePassed !== true
		|| installation.platform !== platform
		|| installation.architecture !== summary.environment.architecture) {
		fail(`performance receipt on ${platform} did not measure the proven isolated installation`)
	}
	for (const field of ['haxe', 'haxelib', 'ocamlc', 'dune', 'node']) {
		if (!summary.environment.toolchain || !installation.toolchain
			|| summary.environment.toolchain[field] === 'unknown'
			|| summary.environment.toolchain[field] !== installation.toolchain[field]) {
			fail(`performance receipt on ${platform} has inconsistent ${field} toolchain evidence`)
		}
	}
	if (!Array.isArray(summary.scenarios) || summary.scenarios.length !== scenarioContract.size) {
		fail(`performance receipt on ${platform} must contain six scenarios`)
	}
	const ids = summary.scenarios.map(scenario => scenario.id)
	if (new Set(ids).size !== scenarioContract.size || [...scenarioContract.keys()].some(id => !ids.includes(id))) {
		fail(`performance receipt on ${platform} has an incomplete or duplicate scenario set`)
	}
	const scenarios = summary.scenarios.map(scenario => validateScenario(scenario, platform))
	const iteration = validateIteration(summary.iteration, platform)
	const portable = scenarios.find(scenario => scenario.id === 'ro-perf-05')
	const metal = scenarios.find(scenario => scenario.id === 'ro-perf-06')
	const expectedProfile = {
		runMedianPctOfPortable: Math.round((metal.measured.run.medianMs / portable.measured.run.medianMs) * 100),
		buildMedianPctOfPortable: Math.round((metal.measured.build.medianMs / portable.measured.build.medianMs) * 100)
	}
	for (const [field, value] of Object.entries(expectedProfile)) {
		if (!summary.profileComparison || summary.profileComparison[field] !== value) {
			fail(`performance receipt on ${platform} has an invalid ${field} profile ratio`)
		}
	}
	return {
		platform,
		architecture: summary.environment.architecture,
		environment: summary.environment,
		provenance,
		scenarios,
		iteration,
		profileComparison: summary.profileComparison
	}
}

function main() {
	const values = parseArgs(process.argv.slice(2))
	const manifestPath = path.resolve(values['artifact-manifest'])
	const manifest = loadArtifactManifest(manifestPath)
	if (manifest.schemaVersion !== 1 || manifest.marker !== 'RO_PACKAGE_ARTIFACT:PASS' || manifest.workingTreeDirty !== false) {
		fail('shared package artifact was not produced from a clean checkout')
	}
	const manifestSha256 = sha256File(manifestPath)
	const summaries = findSummaries(path.resolve(values['evidence-root']))
	if (summaries.length !== 2) {
		fail(`expected two platform performance summaries, received ${summaries.length}`)
	}
	const hosts = summaries.map(summary => validateConsumer(summary, manifest, manifestSha256))
	hosts.sort((left, right) => left.platform.localeCompare(right.platform))
	if (hosts.map(host => host.platform).join(',') !== 'darwin,linux') {
		fail(`expected darwin and linux performance hosts, received ${hosts.map(host => host.platform).join(',')}`)
	}
	const result = {
		schemaVersion: 2,
		marker: 'RO_TARGET_PERF_PLATFORM_MATRIX:PASS',
		implementationCommit: manifest.implementationCommit,
		artifactManifestSha256: manifestSha256,
		package: manifest.package,
		comparisonPolicy: {
			perHostMeasurementsOnly: true,
			absoluteTimingAcrossHosts: 'forbidden',
			reason: 'Linux and macOS hosted runners have different hardware and scheduling conditions.'
		},
		hosts
	}
	const output = path.resolve(values.out)
	fs.mkdirSync(path.dirname(output), { recursive: true })
	fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n')
	console.log(`[reflaxe-ocaml-perf-matrix] packageSha256=${manifest.package.sha256}`)
	console.log(result.marker)
}

if (require.main === module) {
	try {
		main()
	} catch (error) {
		console.error(`[reflaxe-ocaml-perf-matrix] ERROR: ${error instanceof Error ? error.message : String(error)}`)
		process.exitCode = 1
	}
}

module.exports = { validateStats }
