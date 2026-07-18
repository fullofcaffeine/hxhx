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
	}
	return {
		id: scenario.id,
		kind: scenario.kind,
		measured: scenario.measured,
		verification: scenario.verification,
		comparisons: scenario.comparisons
	}
}

function validateConsumer(summary, manifest, manifestSha256) {
	assertNoAbsolutePaths(summary)
	const platform = summary.environment && summary.environment.platform
	if (summary.schemaVersion !== 1 || summary.marker !== 'RO_TARGET_PERF_PLATFORM:PASS' || summary.mode !== 'platform-report') {
		fail(`performance receipt on ${platform || '(unknown)'} did not pass`)
	}
	if (!summary.method
		|| summary.method.id !== 'installed-package-platform-v1'
		|| summary.method.rawSamplesRetained !== true
		|| summary.method.sampleOrderPreserved !== true
		|| summary.method.outputDirectoryRemovedBeforeEachBuild !== true
		|| summary.method.sharedToolchainCachesMayRemainWarm !== true
		|| summary.method.runtimeVerificationExcludedFromBuildTiming !== true
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
		schemaVersion: 1,
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
