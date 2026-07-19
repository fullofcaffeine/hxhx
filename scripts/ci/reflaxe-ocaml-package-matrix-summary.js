#!/usr/bin/env node
/** Combines Linux and macOS package-install receipts for one immutable ZIP. */
const fs = require('fs')
const path = require('path')

const { loadArtifactManifest, sha256File } = require('../release/reflaxe-ocaml-package-artifact')

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

function validateConsumer(summary, manifest, manifestSha256) {
	if (summary.marker !== 'RO_PACKAGE_INSTALL_SMOKE:PASS') {
		fail(`package consumer on ${summary.platform || '(unknown)'} did not pass`)
	}
	if (summary.implementationCommit !== manifest.implementationCommit || summary.workingTreeDirty !== false) {
		fail(`package consumer on ${summary.platform} is not tied to the clean artifact commit`)
	}
	if (summary.package.buildMode !== 'supplied' || summary.package.producerCommit !== manifest.implementationCommit) {
		fail(`package consumer on ${summary.platform} did not use the shared artifact`)
	}
	if (summary.package.producerWorkingTreeDirty !== false || summary.package.artifactManifestSha256 !== manifestSha256) {
		fail(`package consumer on ${summary.platform} has different artifact provenance`)
	}
	for (const field of ['name', 'version', 'archiveFile', 'sha256', 'bytes', 'sourceOnly', 'fileCount', 'reproducible']) {
		if (summary.package[field] !== manifest.package[field]) {
			fail(`package consumer on ${summary.platform} disagrees on ${field}`)
		}
	}
	if (!summary.evidence || summary.evidence.machineLocalPathsRedacted !== true) {
		fail(`package consumer on ${summary.platform} did not sanitize evidence`)
	}
	for (const field of ['scaffoldCommandPassed', 'scaffoldApplicationPassed', 'scaffoldLibraryPassed', 'inspectCommandPassed', 'buildCommandPassed']) {
		if (!summary.tooling || summary.tooling[field] !== true) {
			fail(`package consumer on ${summary.platform} did not prove tooling.${field}`)
		}
	}
	for (const field of ['compilePassed', 'nativeBuildPassed', 'runtimePassed', 'stdoutMatched']) {
		if (!summary.externalApplication || summary.externalApplication[field] !== true) {
			fail(`package consumer on ${summary.platform} did not prove ${field}`)
		}
	}
	return {
		platform: summary.platform,
		architecture: summary.architecture,
		toolchain: summary.toolchain,
		installedTargetRelativePath: summary.isolation.installedTargetRelativePath,
		emittedSourceSha256: summary.externalApplication.emittedSourceSha256,
		executableSha256: summary.externalApplication.executableSha256,
		stdoutSha256: summary.externalApplication.stdoutSha256,
		timingsMs: summary.timingsMs
	}
}

function main() {
	const values = parseArgs(process.argv.slice(2))
	const manifestPath = path.resolve(values['artifact-manifest'])
	const manifest = loadArtifactManifest(manifestPath)
	if (manifest.marker !== 'RO_PACKAGE_ARTIFACT:PASS' || manifest.workingTreeDirty !== false) {
		fail('shared package artifact was not produced from a clean checkout')
	}
	const manifestSha256 = sha256File(manifestPath)
	const summaries = findSummaries(path.resolve(values['evidence-root']))
	if (summaries.length !== 2) {
		fail(`expected two platform summaries, received ${summaries.length}`)
	}
	const consumers = summaries.map(summary => validateConsumer(summary, manifest, manifestSha256))
	consumers.sort((left, right) => (left.platform < right.platform ? -1 : left.platform > right.platform ? 1 : 0))
	if (consumers.map(consumer => consumer.platform).join(',') !== 'darwin,linux') {
		fail(`expected darwin and linux consumers, received ${consumers.map(consumer => consumer.platform).join(',')}`)
	}
	const result = {
		schemaVersion: 1,
		marker: 'RO_PACKAGE_ARTIFACT_MATRIX:PASS',
		implementationCommit: manifest.implementationCommit,
		artifactManifestSha256: manifestSha256,
		package: manifest.package,
		consumers
	}
	const output = path.resolve(values.out)
	fs.mkdirSync(path.dirname(output), { recursive: true })
	fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n')
	console.log(`[reflaxe-ocaml-package-matrix] sha256=${manifest.package.sha256}`)
	console.log(result.marker)
}

try {
	main()
} catch (error) {
	console.error(`[reflaxe-ocaml-package-matrix] ERROR: ${error instanceof Error ? error.message : String(error)}`)
	process.exit(1)
}
