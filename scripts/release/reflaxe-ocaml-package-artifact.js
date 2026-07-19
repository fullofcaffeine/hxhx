#!/usr/bin/env node
/**
 * Inspects and records the immutable reflaxe.ocaml source package artifact.
 *
 * The resulting manifest is safe to pass between CI jobs: it contains package
 * identity and repository provenance, but never a machine-local path.
 */
const cp = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const defaultEpochSeconds = 315532800
const defaultPackageMetadata = JSON.parse(fs.readFileSync(path.join(repoRoot, 'packages/reflaxe.ocaml/haxelib.json'), 'utf8'))
const packageRunner = 'reflaxe.ocaml.tooling.ReflaxeOcamlRun'
const requiredArchiveFiles = ['haxelib.json', 'extraParams.hxml', 'src/reflaxe/ocaml/tooling/ReflaxeOcamlRun.hx', 'src/reflaxe/ocaml/OcamlCompiler.hx']
const forbiddenArchiveExtensions = new Set([
	'.a',
	'.cma',
	'.cmi',
	'.cmo',
	'.cmx',
	'.cmxa',
	'.cmxs',
	'.dll',
	'.dylib',
	'.exe',
	'.n',
	'.ndll',
	'.o',
	'.obj',
	'.so'
])

function sha256File(filePath) {
	return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function run(command, args, options = {}) {
	return cp.spawnSync(command, args, {
		cwd: options.cwd || repoRoot,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
}

function requireSuccess(label, result) {
	if (result.status !== 0) {
		throw new Error(`${label} failed with exit ${result.status}: ${String(result.stderr || result.stdout || '').trim()}`)
	}
	return result
}

function readArchiveEntries(zipPath) {
	requireSuccess('ZIP integrity check', run('unzip', ['-tqq', zipPath]))
	const listing = requireSuccess('ZIP listing', run('unzip', ['-Z1', zipPath]))
	const entries = listing.stdout.split(/\r?\n/).filter(Boolean)
	if (entries.length === 0) {
		throw new Error('release archive is empty')
	}
	if (new Set(entries).size !== entries.length) {
		throw new Error('release archive contains duplicate paths')
	}
	for (const entry of entries) {
		if (entry.includes('\\') || entry.includes('\r') || entry.includes('\n') || entry.endsWith('/')) {
			throw new Error(`release archive contains a non-canonical file path: ${entry}`)
		}
		if (path.posix.isAbsolute(entry) || entry.split('/').includes('..')) {
			throw new Error(`unsafe path in release archive: ${entry}`)
		}
		if (forbiddenArchiveExtensions.has(path.posix.extname(entry).toLowerCase())) {
			throw new Error(`compiler/host-specific artifact leaked into release archive: ${entry}`)
		}
	}
	for (const required of requiredArchiveFiles) {
		if (!entries.includes(required)) {
			throw new Error(`release archive is missing ${required}`)
		}
	}
	return entries
}

function readEmbeddedMetadata(zipPath) {
	const result = requireSuccess('embedded haxelib.json read', run('unzip', ['-p', zipPath, 'haxelib.json']))
	try {
		return JSON.parse(result.stdout)
	} catch (error) {
		throw new Error(`embedded haxelib.json is invalid JSON: ${error instanceof Error ? error.message : String(error)}`)
	}
}

/** Validates archive identity and returns the package fields used by evidence. */
function inspectPackageArchive(zipPath, expectedMetadata = defaultPackageMetadata) {
	const absoluteZip = path.resolve(zipPath)
	if (!fs.existsSync(absoluteZip) || !fs.statSync(absoluteZip).isFile()) {
		throw new Error(`package ZIP does not exist: ${absoluteZip}`)
	}
	const archiveFile = `${expectedMetadata.name}-${expectedMetadata.version}.zip`
	if (path.basename(absoluteZip) !== archiveFile) {
		throw new Error(`package ZIP filename must be ${archiveFile}, received ${path.basename(absoluteZip)}`)
	}
	const entries = readArchiveEntries(absoluteZip)
	const embedded = readEmbeddedMetadata(absoluteZip)
	if (embedded.name !== expectedMetadata.name || embedded.version !== expectedMetadata.version) {
		throw new Error(
			`embedded package identity must be ${expectedMetadata.name} ${expectedMetadata.version}, received ${embedded.name || '(missing)'} ${embedded.version || '(missing)'}`
		)
	}
	if (embedded.main !== packageRunner) {
		throw new Error(`embedded package runner must be ${packageRunner}, received ${embedded.main || '(missing)'}`)
	}
	return {
		name: expectedMetadata.name,
		version: expectedMetadata.version,
		archiveFile,
		sha256: sha256File(absoluteZip),
		bytes: fs.statSync(absoluteZip).size,
		sourceOnly: true,
		fileCount: entries.length
	}
}

function createArtifactManifest(packageInfo, options) {
	if (!/^[0-9a-f]{40}$/.test(options.implementationCommit || '')) {
		throw new Error('artifact implementation commit must be a lowercase 40-character Git SHA')
	}
	if (typeof options.workingTreeDirty !== 'boolean') {
		throw new Error('artifact workingTreeDirty must be Boolean')
	}
	if (options.reproducible !== true) {
		throw new Error('artifact manifest requires a reproducible package build')
	}
	return {
		schemaVersion: 1,
		marker: 'RO_PACKAGE_ARTIFACT:PASS',
		implementationCommit: options.implementationCommit,
		workingTreeDirty: options.workingTreeDirty,
		sourceDateEpoch: options.sourceDateEpoch || defaultEpochSeconds,
		package: {
			...packageInfo,
			reproducible: true
		}
	}
}

function loadArtifactManifest(manifestPath) {
	try {
		return JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
	} catch (error) {
		throw new Error(`package artifact manifest is invalid: ${error instanceof Error ? error.message : String(error)}`)
	}
}

/** Proves that a downloaded ZIP is exactly the artifact described by its producer. */
function validateArtifactManifest(manifest, packageInfo, expectedCommit) {
	if (manifest.schemaVersion !== 1 || manifest.marker !== 'RO_PACKAGE_ARTIFACT:PASS') {
		throw new Error('package artifact manifest has an unsupported schema or missing pass marker')
	}
	if (!/^[0-9a-f]{40}$/.test(manifest.implementationCommit || '')) {
		throw new Error('package artifact manifest has an invalid implementation commit')
	}
	if (expectedCommit && manifest.implementationCommit !== expectedCommit) {
		throw new Error(`package artifact commit ${manifest.implementationCommit} does not match checkout ${expectedCommit}`)
	}
	if (typeof manifest.workingTreeDirty !== 'boolean' || !Number.isInteger(manifest.sourceDateEpoch)) {
		throw new Error('package artifact manifest provenance fields are invalid')
	}
	for (const field of ['name', 'version', 'archiveFile', 'sha256', 'bytes', 'sourceOnly', 'fileCount']) {
		if (!manifest.package || manifest.package[field] !== packageInfo[field]) {
			throw new Error(`package artifact manifest ${field} does not match the downloaded ZIP`)
		}
	}
	if (manifest.package.reproducible !== true) {
		throw new Error('package artifact manifest does not prove reproducible construction')
	}
	return manifest
}

function gitOutput(args) {
	return requireSuccess(`git ${args.join(' ')}`, run('git', args)).stdout.trim()
}

function parseArgs(argv) {
	const [command, ...rest] = argv
	const values = {}
	for (let index = 0; index < rest.length; index += 2) {
		const key = rest[index]
		const value = rest[index + 1]
		if (!key || !key.startsWith('--') || value == null) {
			throw new Error(`invalid arguments: ${rest.join(' ')}`)
		}
		values[key.slice(2)] = value
	}
	return { command, values }
}

function runCli() {
	const { command, values } = parseArgs(process.argv.slice(2))
	if (command !== 'record' || !values.zip || !values.out) {
		throw new Error('usage: reflaxe-ocaml-package-artifact.js record --zip <archive> --out <manifest>')
	}
	const packageInfo = inspectPackageArchive(values.zip)
	const manifest = createArtifactManifest(packageInfo, {
		implementationCommit: gitOutput(['rev-parse', 'HEAD']),
		workingTreeDirty: gitOutput(['status', '--porcelain']).length > 0,
		reproducible: true,
		sourceDateEpoch: Number(process.env.SOURCE_DATE_EPOCH || defaultEpochSeconds)
	})
	const output = path.resolve(values.out)
	fs.mkdirSync(path.dirname(output), { recursive: true })
	fs.writeFileSync(output, JSON.stringify(manifest, null, 2) + '\n')
	console.log(`[reflaxe-ocaml-package-artifact] sha256=${packageInfo.sha256}`)
	console.log(manifest.marker)
}

if (require.main === module) {
	try {
		runCli()
	} catch (error) {
		console.error(`[reflaxe-ocaml-package-artifact] ERROR: ${error instanceof Error ? error.message : String(error)}`)
		process.exit(1)
	}
}

module.exports = {
	createArtifactManifest,
	defaultEpochSeconds,
	inspectPackageArchive,
	loadArtifactManifest,
	sha256File,
	validateArtifactManifest
}
