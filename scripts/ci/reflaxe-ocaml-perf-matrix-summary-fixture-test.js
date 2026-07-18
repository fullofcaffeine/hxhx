#!/usr/bin/env node
/** Exercises both accepted and deliberately invalid platform performance receipts. */
const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { sha256File } = require('../release/reflaxe-ocaml-package-artifact')

const script = path.join(__dirname, 'reflaxe-ocaml-perf-matrix-summary.js')
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-perf-matrix-fixture-'))
const consumersRoot = path.join(tempRoot, 'consumers')
const outputPath = path.join(tempRoot, 'aggregate', 'summary.json')

function stats(samples) {
	const sorted = [...samples].sort((left, right) => left - right)
	const middle = Math.floor(sorted.length / 2)
	return {
		samplesMs: samples,
		reps: samples.length,
		avgMs: Math.round(samples.reduce((sum, value) => sum + value, 0) / samples.length),
		bestMs: Math.min(...samples),
		medianMs: sorted.length % 2 === 1 ? sorted[middle] : Math.round((sorted[middle - 1] + sorted[middle]) / 2),
		worstMs: Math.max(...samples)
	}
}

function scenario(id, kind) {
	const measured = {
		build: stats([100, 110, 120]),
		generatedMlFileCount: 4,
		generatedMlBytes: 1200,
		executableBytes: 2400
	}
	if (kind === 'runtime_bench') {
		measured.run = stats([10, 11, 12, 13, 14, 15, 16, 17, 18])
	}
	return {
		id,
		kind,
		compileStatus: 0,
		runStatus: kind === 'runtime_bench' ? 0 : undefined,
		verification: {
			passed: true,
			stdoutMatches: true,
			expectedStdoutSha256: 'd'.repeat(64),
			actualStdoutSha256: 'd'.repeat(64)
		},
		measured,
		comparisons: {},
		referenceComparisonsEnforced: false,
		passed: true
	}
}

function receipt(platform, architecture, commit, packageInfo, manifestSha256) {
	const toolchain = {
		haxe: '4.3.7',
		haxelib: '4.1.1',
		ocamlc: '5.2.1',
		dune: '3.24.0',
		node: 'v20.20.2'
	}
	return {
		schemaVersion: 1,
		marker: 'RO_TARGET_PERF_PLATFORM:PASS',
		mode: 'platform-report',
		method: {
			id: 'installed-package-platform-v1',
			durationUnit: 'milliseconds',
			rawSamplesRetained: true,
			sampleOrderPreserved: true,
			outputDirectoryRemovedBeforeEachBuild: true,
			sharedToolchainCachesMayRemainWarm: true,
			runtimeVerificationExcludedFromBuildTiming: true,
			crossHostAbsoluteComparisonAllowed: false,
			referenceThresholdsEnforced: false
		},
		referenceBaseline: { path: 'docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json' },
		environment: {
			platform,
			architecture,
			cpu: { count: 4, model: 'fixture CPU' },
			loadAverage: [0, 0, 0],
			totalMemoryBytes: 1000000,
			runnerImage: { runnerOs: platform },
			toolchain
		},
		provenance: {
			implementationCommit: commit,
			workingTreeDirty: false,
			installedPackageProof: true,
			artifactManifestSha256: manifestSha256,
			package: packageInfo,
			installation: {
				buildMode: 'supplied',
				platform,
				architecture,
				toolchain,
				installedTargetRelativePath: 'reflaxe,ocaml/1,2,3/src',
				targetResolvedOutsideCheckout: true,
				isolationSmokePassed: true
			}
		},
		evidence: { machineLocalPathsRedacted: true },
		scenarios: [
			scenario('ro-perf-01', 'build_native'),
			scenario('ro-perf-02', 'build_native'),
			scenario('ro-perf-03', 'build_native'),
			scenario('ro-perf-04', 'build_native'),
			scenario('ro-perf-05', 'runtime_bench'),
			scenario('ro-perf-06', 'runtime_bench')
		],
		profileComparison: {
			runMedianPctOfPortable: 100,
			buildMedianPctOfPortable: 100
		}
	}
}

function run() {
	fs.rmSync(path.dirname(outputPath), { recursive: true, force: true })
	return cp.spawnSync(process.execPath, [
		script,
		'--artifact-manifest', path.join(tempRoot, 'artifact-manifest.json'),
		'--evidence-root', consumersRoot,
		'--out', outputPath
	], { encoding: 'utf8', shell: false })
}

function writeReceipts(baseReceipts, mutate) {
	fs.rmSync(consumersRoot, { recursive: true, force: true })
	const receipts = JSON.parse(JSON.stringify(baseReceipts))
	if (mutate) {
		mutate(receipts)
	}
	for (const [index, summary] of receipts.entries()) {
		const directory = path.join(consumersRoot, `consumer-${index}`)
		fs.mkdirSync(directory, { recursive: true })
		fs.writeFileSync(path.join(directory, 'summary.json'), JSON.stringify(summary, null, 2) + '\n')
	}
}

function expectRejected(baseReceipts, label, mutate, pattern) {
	writeReceipts(baseReceipts, mutate)
	const result = run()
	assert.notStrictEqual(result.status, 0, `${label} unexpectedly passed`)
	assert.match(result.stderr, pattern)
}

try {
	const commit = 'b'.repeat(40)
	const packageInfo = {
		name: 'reflaxe.ocaml',
		version: '1.2.3',
		archiveFile: 'reflaxe.ocaml-1.2.3.zip',
		sha256: 'c'.repeat(64),
		bytes: 123,
		sourceOnly: true,
		fileCount: 3,
		reproducible: true
	}
	const manifestPath = path.join(tempRoot, 'artifact-manifest.json')
	fs.writeFileSync(manifestPath, JSON.stringify({
		schemaVersion: 1,
		marker: 'RO_PACKAGE_ARTIFACT:PASS',
		implementationCommit: commit,
		workingTreeDirty: false,
		sourceDateEpoch: 315532800,
		package: packageInfo
	}, null, 2) + '\n')
	const manifestSha256 = sha256File(manifestPath)
	const baseReceipts = [
		receipt('linux', 'x64', commit, packageInfo, manifestSha256),
		receipt('darwin', 'arm64', commit, packageInfo, manifestSha256)
	]

	writeReceipts(baseReceipts)
	const accepted = run()
	assert.strictEqual(accepted.status, 0, accepted.stderr)
	assert.strictEqual(JSON.parse(fs.readFileSync(outputPath, 'utf8')).marker, 'RO_TARGET_PERF_PLATFORM_MATRIX:PASS')

	expectRejected(baseReceipts, 'different package', receipts => {
		receipts[1].provenance.package.sha256 = '0'.repeat(64)
	}, /disagrees on package sha256/)
	expectRejected(baseReceipts, 'different commit', receipts => {
		receipts[1].provenance.implementationCommit = '0'.repeat(40)
	}, /not tied to the clean package commit/)
	expectRejected(baseReceipts, 'duplicate host', receipts => {
		receipts[1].environment.platform = 'linux'
		receipts[1].provenance.installation.platform = 'linux'
	}, /expected darwin and linux/)
	expectRejected(baseReceipts, 'missing raw sample', receipts => {
		receipts[0].scenarios[0].measured.build.samplesMs.pop()
	}, /retain exactly 3 raw samples/)
	expectRejected(baseReceipts, 'wrong output', receipts => {
		receipts[0].scenarios[0].verification.stdoutMatches = false
	}, /did not verify runtime output/)
	expectRejected(baseReceipts, 'negative duration', receipts => {
		receipts[0].scenarios[4].measured.run.samplesMs[0] = -1
	}, /finite number >= 0/)
	expectRejected(baseReceipts, 'checkout fallback', receipts => {
		receipts[0].provenance.installation.targetResolvedOutsideCheckout = false
	}, /did not measure the proven isolated installation/)
	expectRejected(baseReceipts, 'machine-local path', receipts => {
		receipts[0].referenceBaseline.path = '/home/runner/work/private/baseline.json'
	}, /machine-local absolute path/)

	console.log('REFLAXE_OCAML_PERF_MATRIX_SUMMARY_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, { recursive: true, force: true })
}
