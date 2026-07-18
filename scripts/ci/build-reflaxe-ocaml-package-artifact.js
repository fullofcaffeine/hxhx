#!/usr/bin/env node
/**
 * Builds one distributable reflaxe.ocaml ZIP after proving two constructions
 * are byte-identical, then records the immutable artifact manifest for CI.
 */
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const {
	createArtifactManifest,
	defaultEpochSeconds,
	inspectPackageArchive,
	sha256File
} = require('../release/reflaxe-ocaml-package-artifact')

const repoRoot = path.resolve(__dirname, '../..')
const packageMetadata = JSON.parse(fs.readFileSync(path.join(repoRoot, 'packages/reflaxe.ocaml/haxelib.json'), 'utf8'))
const artifactsRoot = path.resolve(process.env.RO_PACKAGE_ARTIFACTS || path.join(repoRoot, '.artifacts/reflaxe-ocaml/package-artifact'))
const archiveFile = `${packageMetadata.name}-${packageMetadata.version}.zip`
const manifestPath = path.join(artifactsRoot, 'artifact-manifest.json')

let tempRoot = null
let evidenceReplacements = []

function normalizeOutput(value) {
	return String(value || '').replace(/\r\n/g, '\n')
}

function addEvidenceReplacement(value, replacement) {
	if (!value) {
		return
	}
	const resolved = path.resolve(value)
	for (const candidate of new Set([resolved, fs.existsSync(resolved) ? fs.realpathSync(resolved) : null].filter(Boolean))) {
		evidenceReplacements.push([candidate, replacement])
	}
}

function sanitizeEvidence(value) {
	let sanitized = normalizeOutput(value)
	for (const [localPath, replacement] of evidenceReplacements) {
		sanitized = sanitized.split(localPath).join(replacement)
	}
	return sanitized
}

function runStep(name, command, args, options = {}) {
	const result = cp.spawnSync(command, args, {
		cwd: options.cwd || repoRoot,
		env: options.env || process.env,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
	fs.writeFileSync(path.join(artifactsRoot, `${name}.stdout.log`), sanitizeEvidence(result.stdout))
	fs.writeFileSync(path.join(artifactsRoot, `${name}.stderr.log`), sanitizeEvidence(result.stderr || result.error))
	if (result.status !== 0) {
		throw new Error(`${name} failed with exit ${result.status == null ? 1 : result.status}; see ${name}.stderr.log`)
	}
	return normalizeOutput(result.stdout)
}

function verifyEvidenceLogs() {
	for (const file of fs.readdirSync(artifactsRoot).filter(name => name.endsWith('.log'))) {
		const contents = fs.readFileSync(path.join(artifactsRoot, file), 'utf8')
		for (const [localPath] of evidenceReplacements) {
			if (contents.includes(localPath)) {
				throw new Error(`machine-local path remained in evidence log ${file}`)
			}
		}
	}
}

function main() {
	fs.rmSync(artifactsRoot, { recursive: true, force: true })
	fs.mkdirSync(artifactsRoot, { recursive: true })
	tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-artifact-'))
	addEvidenceReplacement(tempRoot, '<temp>')
	addEvidenceReplacement(artifactsRoot, '<artifacts>')
	addEvidenceReplacement(repoRoot, '<repo>')
	addEvidenceReplacement(os.homedir(), '<home>')
	evidenceReplacements.sort((left, right) => right[0].length - left[0].length)

	try {
		const buildA = path.join(tempRoot, 'build-a')
		const buildB = path.join(tempRoot, 'build-b')
		const builderTemp = path.join(tempRoot, 'builder-tmp')
		fs.mkdirSync(buildA, { recursive: true })
		fs.mkdirSync(buildB, { recursive: true })
		fs.mkdirSync(builderTemp, { recursive: true })
		const env = {
			...process.env,
			SOURCE_DATE_EPOCH: process.env.SOURCE_DATE_EPOCH || String(defaultEpochSeconds),
			TMPDIR: builderTemp,
			TEMP: builderTemp,
			TMP: builderTemp
		}
		runStep('build-a', 'bash', ['scripts/release/build-haxelib-zip.sh', '--out-dir', buildA], { env })
		runStep('build-b', 'bash', ['scripts/release/build-haxelib-zip.sh', '--out-dir', buildB], { env })
		const zipA = path.join(buildA, archiveFile)
		const zipB = path.join(buildB, archiveFile)
		const hashA = sha256File(zipA)
		const hashB = sha256File(zipB)
		if (hashA !== hashB) {
			throw new Error(`two package builds produced different SHA-256 values: ${hashA} != ${hashB}`)
		}

		const outputZip = path.join(artifactsRoot, archiveFile)
		fs.copyFileSync(zipA, outputZip)
		const packageInfo = inspectPackageArchive(outputZip)
		const implementationCommit = runStep('implementation-commit', 'git', ['rev-parse', 'HEAD']).trim()
		const workingTreeDirty = runStep('working-tree-status', 'git', ['status', '--porcelain']).trim().length > 0
		const manifest = createArtifactManifest(packageInfo, {
			implementationCommit,
			workingTreeDirty,
			reproducible: true,
			sourceDateEpoch: Number(env.SOURCE_DATE_EPOCH)
		})
		fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n')
		verifyEvidenceLogs()
		console.log(`[reflaxe-ocaml-package-builder] archive_sha256=${packageInfo.sha256}`)
		console.log(manifest.marker)
	} catch (error) {
		const message = sanitizeEvidence(error instanceof Error ? error.message : String(error))
		fs.writeFileSync(path.join(artifactsRoot, 'failure.json'), JSON.stringify({
			schemaVersion: 1,
			marker: 'RO_PACKAGE_ARTIFACT:FAIL',
			error: message
		}, null, 2) + '\n')
		console.error(`[reflaxe-ocaml-package-builder] ERROR: ${message}`)
		process.exitCode = 1
	} finally {
		fs.rmSync(tempRoot, { recursive: true, force: true })
	}
}

main()
