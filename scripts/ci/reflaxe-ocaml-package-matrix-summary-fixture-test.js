#!/usr/bin/env node
/** Proves the aggregate rejects host receipts from different package artifacts. */
const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { sha256File } = require('../release/reflaxe-ocaml-package-artifact')

const script = path.join(__dirname, 'reflaxe-ocaml-package-matrix-summary.js')
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-matrix-fixture-'))

function run() {
	return cp.spawnSync(process.execPath, [
		script,
		'--artifact-manifest', path.join(tempRoot, 'artifact-manifest.json'),
		'--evidence-root', path.join(tempRoot, 'consumers'),
		'--out', path.join(tempRoot, 'summary.json')
	], { encoding: 'utf8', shell: false })
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
	for (const platform of ['linux', 'darwin']) {
		const directory = path.join(tempRoot, 'consumers', platform)
		fs.mkdirSync(directory, { recursive: true })
		fs.writeFileSync(path.join(directory, 'summary.json'), JSON.stringify({
			marker: 'RO_PACKAGE_INSTALL_SMOKE:PASS',
			implementationCommit: commit,
			workingTreeDirty: false,
			platform,
			architecture: 'x64',
			toolchain: { haxe: '4.3.7' },
			evidence: { machineLocalPathsRedacted: true },
			tooling: {
				scaffoldCommandPassed: true,
				scaffoldApplicationPassed: true,
				scaffoldLibraryPassed: true,
				buildCommandPassed: true
			},
			package: {
				...packageInfo,
				buildMode: 'supplied',
				producerCommit: commit,
				producerWorkingTreeDirty: false,
				artifactManifestSha256: manifestSha256
			},
			isolation: { installedTargetRelativePath: 'reflaxe,ocaml/1,2,3/src' },
			externalApplication: {
				compilePassed: true,
				nativeBuildPassed: true,
				runtimePassed: true,
				stdoutMatched: true,
				emittedSourceSha256: 'd'.repeat(64),
				executableSha256: 'e'.repeat(64),
				stdoutSha256: 'f'.repeat(64)
			},
			timingsMs: { compile: 1 }
		}, null, 2) + '\n')
	}

	const accepted = run()
	assert.strictEqual(accepted.status, 0, accepted.stderr)
	assert.strictEqual(JSON.parse(fs.readFileSync(path.join(tempRoot, 'summary.json'), 'utf8')).marker, 'RO_PACKAGE_ARTIFACT_MATRIX:PASS')

	const darwinPath = path.join(tempRoot, 'consumers/darwin/summary.json')
	const darwin = JSON.parse(fs.readFileSync(darwinPath, 'utf8'))
	darwin.tooling.scaffoldCommandPassed = false
	fs.writeFileSync(darwinPath, JSON.stringify(darwin, null, 2) + '\n')
	const missingScaffold = run()
	assert.notStrictEqual(missingScaffold.status, 0)
	assert.match(missingScaffold.stderr, /tooling\.scaffoldCommandPassed/)

	darwin.tooling.scaffoldCommandPassed = true
	darwin.package.sha256 = '0'.repeat(64)
	fs.writeFileSync(darwinPath, JSON.stringify(darwin, null, 2) + '\n')
	const rejected = run()
	assert.notStrictEqual(rejected.status, 0)
	assert.match(rejected.stderr, /disagrees on sha256/)

	console.log('REFLAXE_OCAML_PACKAGE_MATRIX_SUMMARY_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, { recursive: true, force: true })
}
