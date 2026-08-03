#!/usr/bin/env node
/**
 * Proves that the release-shaped reflaxe.ocaml ZIP works without checkout
 * resolution, then records sanitized package, toolchain, and runtime evidence.
 */
const cp = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const {
	inspectPackageArchive,
	loadArtifactManifest,
	sha256File,
	validateArtifactManifest
} = require('../release/reflaxe-ocaml-package-artifact')

const repoRoot = path.resolve(__dirname, '../..')
const fixtureRoot = path.join(repoRoot, 'test/packaging/reflaxe_ocaml_external_app')
const artifactsRoot = path.resolve(process.env.RO_PACKAGE_INSTALL_ARTIFACTS || path.join(repoRoot, '.artifacts/reflaxe-ocaml/package-install'))
const packageMetadata = JSON.parse(fs.readFileSync(path.join(repoRoot, 'packages/reflaxe.ocaml/haxelib.json'), 'utf8'))
const expectedHaxeVersion = '4.3.7'
const expectedReflaxeCommit = 'ad25a8ba52adf48a7bf69c5311b274f1c9417ba6'
const expectedReflaxeContentSha256 = '65f5cb6406cfb90d5aea72b4c4d7471059446a48672f0122a424e0bd549bcad7'
const summary = {
	schemaVersion: 1,
	marker: 'RO_PACKAGE_INSTALL_SMOKE:FAIL',
	implementationCommit: null,
	workingTreeDirty: null,
	platform: process.platform,
	architecture: process.arch,
	toolchain: {},
	evidence: {
		machineLocalPathsRedacted: false
	},
	package: {
		name: packageMetadata.name,
		version: packageMetadata.version,
		archiveFile: `reflaxe.ocaml-${packageMetadata.version}.zip`,
		sha256: null,
		bytes: null,
		reproducible: false,
		sourceOnly: false,
		fileCount: 0,
		buildMode: null,
		producerCommit: null,
		producerWorkingTreeDirty: null,
		artifactManifestSha256: null
	},
	isolation: {
		missingTargetRejected: false,
		missingTargetDiagnosticNamedLibrary: false,
		installedTargetInsideDisposableRepository: false,
		installedTargetRelativePath: null,
		resolvedLibraries: []
	},
	tooling: {
		doctorPassed: false,
		doctorSchemaVersion: null,
		sourceGenerationReady: false,
		nativeBuildReady: false,
		scaffoldCommandPassed: false,
		scaffoldApplicationPassed: false,
		scaffoldLibraryPassed: false,
		inspectCommandPassed: false,
		timingReportPassed: false,
		nativeDuneBuildMilliseconds: null,
		buildCommandPassed: false
	},
	externalApplication: {
		compilePassed: false,
		nativeBuildPassed: false,
		runtimePassed: false,
		stdoutMatched: false,
		emittedSourceExcludedFiles: ['ocaml_build_timing_report.json'],
		emittedSourceSha256: null,
		executableSha256: null,
		stdoutSha256: null
	},
	timingsMs: {},
	error: null
}

let tempRoot = null
let evidenceReplacements = []

const performanceEnvironmentKeys = [
	'HAXELIB_PATH',
	'HAXE_STD_PATH',
	'HAXEPATH',
	'NEKOPATH',
	'DYLD_LIBRARY_PATH',
	'LD_LIBRARY_PATH',
	'PATH'
]

function fail(message) {
	throw new Error(message)
}

function ensureDir(directory) {
	fs.mkdirSync(directory, { recursive: true })
}

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
	const startedAt = Date.now()
	const result = cp.spawnSync(command, args, {
		cwd: options.cwd || repoRoot,
		env: options.env || process.env,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
	const status = result.status == null ? 1 : result.status
	const stdout = normalizeOutput(result.stdout)
	const stderr = normalizeOutput(result.stderr || (result.error ? String(result.error) : ''))
	fs.writeFileSync(path.join(artifactsRoot, `${name}.stdout.log`), sanitizeEvidence(stdout))
	fs.writeFileSync(path.join(artifactsRoot, `${name}.stderr.log`), sanitizeEvidence(stderr))
	summary.timingsMs[name] = Date.now() - startedAt
	return { status, stdout, stderr }
}

function requireSuccess(name, result) {
	if (result.status !== 0) {
		fail(`${name} failed with exit ${result.status}; see ${name}.stderr.log`)
	}
	return result
}

function walkFiles(root, options = {}) {
	const files = []
	function visit(current) {
		for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
			if (options.skipDirectory && entry.isDirectory() && options.skipDirectory(entry.name)) {
				continue
			}
			const absolute = path.join(current, entry.name)
			if (entry.isDirectory()) {
				visit(absolute)
			} else if (entry.isFile()) {
				const relative = path.relative(root, absolute).split(path.sep).join('/')
				if (options.skipFile && options.skipFile(relative)) {
					continue
				}
				files.push({
					absolute,
					relative
				})
			} else {
				fail(`unexpected non-file output: ${path.relative(root, absolute)}`)
			}
		}
	}
	visit(root)
	files.sort((left, right) => (left.relative < right.relative ? -1 : left.relative > right.relative ? 1 : 0))
	return files
}

function isInside(parent, child) {
	const relative = path.relative(parent, child)
	return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))
}

/**
 * Reads the compiler-owned source revision instead of hashing volatile reports.
 * The manifest itself inventories timing evidence, but its source-bundle view
 * deliberately excludes that evidence from reproducible source identity.
 */
function generatedSourceRevision(outputDirectory) {
	const manifestPath = path.join(outputDirectory, 'ocaml_artifact_manifest.json')
	if (!fs.existsSync(manifestPath)) {
		fail('generated OCaml output is missing ocaml_artifact_manifest.json')
	}
	const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
	if (manifest.schemaVersion !== 1 || manifest.model !== 'reflaxe-ocaml-artifact-manifest') {
		fail('generated OCaml output has an unsupported artifact manifest')
	}
	if (manifest.summary?.completeForSourceBundle !== true
		|| !Array.isArray(manifest.summary?.blockers)
		|| manifest.summary.blockers.length !== 0) {
		fail('generated artifact manifest did not close every generated-source replay authority')
	}
	const timing = manifest.entries?.find(entry => entry.path === 'ocaml_build_timing_report.json')
	if (!timing || timing.stability !== 'volatile' || timing.includeInSourceBundle !== false) {
		fail('generated artifact manifest did not separate volatile timing from source-bundle identity')
	}
	const revision = manifest.summary?.sourceBundleRevision
	if (typeof revision !== 'string' || !/^sha256:[0-9a-f]{64}$/.test(revision)) {
		fail('generated artifact manifest has an invalid source-bundle revision')
	}
	return revision.slice('sha256:'.length)
}

/**
 * Returns only the path overrides needed to reuse the proven disposable
 * package installation. Keeping the allowlist explicit prevents CI secrets
 * from entering the private handoff file used by the performance runner.
 */
function performanceEnvironment(env) {
	const selected = {}
	for (const key of performanceEnvironmentKeys) {
		if (typeof env[key] === 'string' && env[key]) {
			selected[key] = env[key]
		}
	}
	return selected
}

function prepareTempRoot() {
	const retainedRoot = process.env.RO_PACKAGE_INSTALL_RETAIN_ROOT
		? path.resolve(process.env.RO_PACKAGE_INSTALL_RETAIN_ROOT)
		: null
	const environmentFile = process.env.RO_PACKAGE_INSTALL_ENV_FILE
		? path.resolve(process.env.RO_PACKAGE_INSTALL_ENV_FILE)
		: null
	if (environmentFile && !retainedRoot) {
		fail('RO_PACKAGE_INSTALL_ENV_FILE requires RO_PACKAGE_INSTALL_RETAIN_ROOT')
	}
	if (retainedRoot && isInside(repoRoot, retainedRoot)) {
		fail('retained package installation must live outside the repository checkout')
	}
	if (environmentFile && isInside(repoRoot, environmentFile)) {
		fail('private package environment handoff must live outside the repository checkout')
	}
	if (retainedRoot) {
		fs.rmSync(retainedRoot, { recursive: true, force: true })
		ensureDir(retainedRoot)
		return retainedRoot
	}
	return fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-install-'))
}

function writePerformanceEnvironment(env) {
	if (!process.env.RO_PACKAGE_INSTALL_ENV_FILE) {
		return
	}
	const destination = path.resolve(process.env.RO_PACKAGE_INSTALL_ENV_FILE)
	ensureDir(path.dirname(destination))
	fs.writeFileSync(destination, JSON.stringify(performanceEnvironment(env), null, 2) + '\n', { mode: 0o600 })
}

function firstClasspath(output) {
	return normalizeOutput(output)
		.split('\n')
		.map(line => line.trim())
		.find(line => line && !line.startsWith('-'))
}

function shellQuote(value) {
	return `'${String(value).replace(/'/g, `'"'"'`)}'`
}

function writeHaxelibWrapper(wrapperPath, haxelibPath, nekoRoot, nekoLibraryDirectories) {
	const libraryPath = nekoLibraryDirectories.join(path.delimiter)
	const contents = `#!/usr/bin/env bash
set -euo pipefail
export NEKOPATH=${shellQuote(nekoRoot)}
export DYLD_LIBRARY_PATH=${shellQuote(libraryPath)}\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}
export LD_LIBRARY_PATH=${shellQuote(libraryPath)}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
exec ${shellQuote(haxelibPath)} "\$@"
`
	fs.writeFileSync(wrapperPath, contents, { mode: 0o755 })
}

/**
 * Finds every directory that can satisfy the stock haxelib client's dynamic
 * libneko dependency. Lix exposes the active Neko files at the package root on
 * some hosts and keeps them below a version directory on others.
 */
function findNekoLibraryDirectories(nekoRoot) {
	const directories = [path.resolve(nekoRoot)]
	const seen = new Set(directories)
	function visit(directory, depth) {
		if (depth > 3) {
			return
		}
		const entries = fs.readdirSync(directory, { withFileTypes: true })
		entries.sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0))
		for (const entry of entries) {
			const absolute = path.join(directory, entry.name)
			if (entry.isDirectory()) {
				visit(absolute, depth + 1)
			} else if ((entry.isFile() || entry.isSymbolicLink()) && /^libneko(?:\.|$)/.test(entry.name)) {
				const parent = path.dirname(absolute)
				if (!seen.has(parent)) {
					seen.add(parent)
					directories.push(parent)
				}
			}
		}
	}
	visit(path.resolve(nekoRoot), 0)
	return directories
}

function commandVersion(name, command, args, options = {}) {
	return requireSuccess(name, runStep(name, command, args, options)).stdout.trim().split('\n')[0]
}

/** Resolves the immutable framework classpath declared by this checkout. */
function resolvePinnedLixReflaxeRoot() {
	const hxmlPath = path.join(repoRoot, 'haxe_libraries/reflaxe.hxml')
	if (!fs.existsSync(hxmlPath)) {
		fail('committed haxe_libraries/reflaxe.hxml is missing')
	}
	const hxml = fs.readFileSync(hxmlPath, 'utf8')
	if (!hxml.includes(expectedReflaxeCommit)) {
		fail(`committed Reflaxe mapping does not name expected commit ${expectedReflaxeCommit}`)
	}
	if (!hxml.includes(expectedReflaxeContentSha256)) {
		fail(`committed Reflaxe mapping does not name expected content digest ${expectedReflaxeContentSha256}`)
	}
	const classpathLine = hxml.split(/\r?\n/).find(line => line.trim().startsWith('-cp '))
	if (!classpathLine) {
		fail('committed Reflaxe mapping has no classpath')
	}
	const cacheRoot = process.env.HAXE_LIBCACHE || path.join(os.homedir(), 'haxe', 'haxe_libraries')
	const classpath = classpathLine.trim().slice(4).trim().replaceAll('${HAXE_LIBCACHE}', cacheRoot)
	let root = path.resolve(classpath)
	if (path.basename(root) === 'src') {
		root = path.dirname(root)
	}
	if (!fs.existsSync(path.join(root, 'Run.hx'))) {
		fail(`pinned Reflaxe framework is not downloaded at ${root}; run npx lix download`)
	}
	return root
}

/** Creates a path-independent digest for an exact framework source tree. */
function sha256Directory(root) {
	const entries = []
	function visit(directory) {
		for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => left.name < right.name ? -1 : left.name > right.name ? 1 : 0)) {
			if (entry.name === '.git') {
				continue
			}
			const absolute = path.join(directory, entry.name)
			if (entry.isDirectory()) {
				visit(absolute)
			} else if (entry.isFile()) {
				entries.push(absolute)
			}
		}
	}
	visit(root)
	const digest = crypto.createHash('sha256')
	for (const absolute of entries) {
		const relative = path.relative(root, absolute).split(path.sep).join('/')
		digest.update(relative)
		digest.update('\0')
		digest.update(fs.readFileSync(absolute))
		digest.update('\0')
	}
	return digest.digest('hex')
}

/** Rejects version-label matches whose actual Reflaxe source bytes differ. */
function validateReflaxeFramework(root) {
	const contentSha256 = sha256Directory(root)
	const hasRemovePureExpressions = fs.existsSync(path.join(root, 'src/reflaxe/preprocessors/implementations/RemovePureExpressionsImpl.hx'))
	summary.toolchain.reflaxe = {
		commit: expectedReflaxeCommit,
		contentSha256,
		hasRemovePureExpressions
	}
	if (contentSha256 !== expectedReflaxeContentSha256) {
		fail(`Reflaxe framework content mismatch: expected ${expectedReflaxeContentSha256}, got ${contentSha256}`)
	}
	if (!hasRemovePureExpressions) {
		fail('pinned Reflaxe framework lacks RemovePureExpressionsImpl')
	}
}

function resolveReflaxeRoot() {
	if (process.env.RO_REFLAXE_ROOT) {
		return path.resolve(process.env.RO_REFLAXE_ROOT)
	}
	return resolvePinnedLixReflaxeRoot()
}

function validatePackageArtifact(zipPath, manifestPath, buildMode) {
	const startedAt = Date.now()
	addEvidenceReplacement(path.dirname(zipPath), '<package-input>')
	addEvidenceReplacement(path.dirname(manifestPath), '<package-input>')
	evidenceReplacements.sort((left, right) => right[0].length - left[0].length)
	const packageInfo = inspectPackageArchive(zipPath, packageMetadata)
	const manifest = validateArtifactManifest(
		loadArtifactManifest(manifestPath),
		packageInfo,
		summary.implementationCommit
	)
	Object.assign(summary.package, packageInfo, {
		reproducible: manifest.package.reproducible,
		buildMode,
		producerCommit: manifest.implementationCommit,
		producerWorkingTreeDirty: manifest.workingTreeDirty,
		artifactManifestSha256: sha256File(manifestPath)
	})
	summary.timingsMs['package-artifact-validate'] = Date.now() - startedAt
	return zipPath
}

function preparePackageArtifact() {
	const suppliedZip = process.env.RO_PACKAGE_INSTALL_ZIP
	const suppliedManifest = process.env.RO_PACKAGE_INSTALL_MANIFEST
	if (Boolean(suppliedZip) !== Boolean(suppliedManifest)) {
		fail('RO_PACKAGE_INSTALL_ZIP and RO_PACKAGE_INSTALL_MANIFEST must be provided together')
	}
	if (suppliedZip) {
		return validatePackageArtifact(path.resolve(suppliedZip), path.resolve(suppliedManifest), 'supplied')
	}

	const packageArtifacts = path.join(artifactsRoot, 'package-artifact')
	const builderTemp = path.join(tempRoot, 'package-builder-tmp')
	ensureDir(builderTemp)
	const buildEnv = {
		...process.env,
		RO_PACKAGE_ARTIFACTS: packageArtifacts,
		TMPDIR: builderTemp,
		TEMP: builderTemp,
		TMP: builderTemp
	}
	requireSuccess(
		'build-package-artifact',
		runStep('build-package-artifact', process.execPath, ['scripts/ci/build-reflaxe-ocaml-package-artifact.js'], { env: buildEnv })
	)
	return validatePackageArtifact(
		path.join(packageArtifacts, summary.package.archiveFile),
		path.join(packageArtifacts, 'artifact-manifest.json'),
		'local-builder'
	)
}

function prepareToolchain(isolatedHaxelib) {
	const selectedVersion = commandVersion('selected-haxe-version', 'haxe', ['--version'])
	if (selectedVersion !== expectedHaxeVersion) {
		fail(`standalone package proof requires Haxe ${expectedHaxeVersion}, received ${selectedVersion}`)
	}

	const haxeRoot = path.resolve(process.env.HAXE_ROOT || path.join(os.homedir(), 'haxe'))
	const compilerRoot = path.join(haxeRoot, 'versions', selectedVersion)
	const haxeBinary = path.resolve(process.env.RO_HAXE_BIN || path.join(compilerRoot, process.platform === 'win32' ? 'haxe.exe' : 'haxe'))
	const haxelibBinary = path.resolve(process.env.RO_HAXELIB_BIN || path.join(compilerRoot, process.platform === 'win32' ? 'haxelib.exe' : 'haxelib'))
	const nekoRoot = path.resolve(process.env.RO_NEKO_ROOT || path.join(haxeRoot, 'neko'))
	for (const [label, file] of [['stock Haxe compiler', haxeBinary], ['stock haxelib client', haxelibBinary]]) {
		if (!fs.existsSync(file)) {
			fail(`${label} was not found at ${file}; set the corresponding RO_HAXE_BIN/RO_HAXELIB_BIN override`)
		}
	}
	if (!fs.existsSync(nekoRoot)) {
		fail(`Neko runtime root was not found; set RO_NEKO_ROOT`)
	}
	if (process.platform === 'win32') {
		fail('the first standalone package proof supports macOS/Linux; Windows clean-install proof remains release-parent scope')
	}

	const wrapperDir = path.join(tempRoot, 'tool-bin')
	ensureDir(wrapperDir)
	const nekoLibraryDirectories = findNekoLibraryDirectories(nekoRoot)
	const nekoLibraryPath = nekoLibraryDirectories.join(path.delimiter)
	writeHaxelibWrapper(path.join(wrapperDir, 'haxelib'), haxelibBinary, nekoRoot, nekoLibraryDirectories)
	const env = {
		...process.env,
		HAXELIB_PATH: isolatedHaxelib,
		HAXE_STD_PATH: path.join(compilerRoot, 'std'),
		HAXEPATH: compilerRoot,
		NEKOPATH: nekoRoot,
		DYLD_LIBRARY_PATH: [nekoLibraryPath, process.env.DYLD_LIBRARY_PATH].filter(Boolean).join(path.delimiter),
		LD_LIBRARY_PATH: [nekoLibraryPath, process.env.LD_LIBRARY_PATH].filter(Boolean).join(path.delimiter),
		PATH: [wrapperDir, compilerRoot, nekoRoot, process.env.PATH].filter(Boolean).join(path.delimiter)
	}

	summary.toolchain.nekoLibraryDirectories = nekoLibraryDirectories.map(directory => {
		const relative = path.relative(nekoRoot, directory).split(path.sep).join('/')
		return relative || '.'
	})
	summary.toolchain.haxe = commandVersion('stock-haxe-version', haxeBinary, ['--version'], { env })
	summary.toolchain.haxelib = commandVersion('stock-haxelib-version', haxelibBinary, ['version'], { env })
	summary.toolchain.ocamlc = commandVersion('ocamlc-version', 'ocamlc', ['-version'], { env })
	summary.toolchain.dune = commandVersion('dune-version', 'dune', ['--version'], { env })
	summary.toolchain.node = process.version
	return { env, haxeBinary, haxelibBinary }
}

function parseLibraryNames(output) {
	return output
		.split('\n')
		.map(line => line.trim())
		.filter(Boolean)
		.map(line => line.split(':')[0])
		.sort()
}

/** Validates the package runner before the external application can mask it. */
function validateInstalledDoctor(doctor, expectedVersion) {
	if (doctor.schemaVersion !== 1 || doctor.packageName !== 'reflaxe.ocaml' || doctor.packageVersion !== expectedVersion) {
		fail('installed reflaxe.ocaml doctor returned an unexpected package/schema identity')
	}
	if (doctor.summary?.requestedCapability !== 'native' || doctor.summary?.ready !== true || doctor.summary?.exitCode !== 0) {
		fail('installed reflaxe.ocaml doctor did not confirm native capability')
	}
	if (doctor.capabilities?.sourceGeneration !== true || doctor.capabilities?.nativeBuild !== true) {
		fail('installed reflaxe.ocaml doctor capability report was incomplete')
	}
	return {
		doctorPassed: true,
		doctorSchemaVersion: doctor.schemaVersion,
		sourceGenerationReady: doctor.capabilities.sourceGeneration,
		nativeBuildReady: doctor.capabilities.nativeBuild
	}
}

function proveExternalInstall(zipPath, reflaxeRoot) {
	const isolatedHaxelib = path.join(tempRoot, 'haxelib')
	const appRoot = path.join(tempRoot, 'external-app')
	ensureDir(isolatedHaxelib)
	fs.cpSync(fixtureRoot, appRoot, { recursive: true })
	const { env, haxeBinary, haxelibBinary } = prepareToolchain(isolatedHaxelib)

	requireSuccess('seed-reflaxe-framework', runStep('seed-reflaxe-framework', haxelibBinary, ['dev', 'reflaxe', reflaxeRoot], { env }))
	const beforeInstall = requireSuccess('libraries-before-install', runStep('libraries-before-install', haxelibBinary, ['list'], { env }))
	const beforeNames = parseLibraryNames(beforeInstall.stdout)
	if (beforeNames.join(',') !== 'reflaxe') {
		fail(`disposable haxelib repository unexpectedly resolved: ${beforeNames.join(', ') || '(none)'}`)
	}

	const missingTarget = runStep('missing-target-negative', haxeBinary, ['build.hxml'], { cwd: appRoot, env })
	const missingDiagnostic = `${missingTarget.stdout}\n${missingTarget.stderr}`
	summary.isolation.missingTargetRejected = missingTarget.status !== 0
	summary.isolation.missingTargetDiagnosticNamedLibrary = missingDiagnostic.includes('reflaxe.ocaml')
	if (!summary.isolation.missingTargetRejected || !summary.isolation.missingTargetDiagnosticNamedLibrary) {
		fail('external compile did not reject the missing reflaxe.ocaml package with a useful diagnostic')
	}

	requireSuccess('install-package', runStep('install-package', haxelibBinary, ['install', zipPath, '--always', '--skip-dependencies'], { env }))
	const libraries = requireSuccess('libraries-after-install', runStep('libraries-after-install', haxelibBinary, ['list'], { env }))
	summary.isolation.resolvedLibraries = parseLibraryNames(libraries.stdout)
	if (summary.isolation.resolvedLibraries.join(',') !== 'reflaxe,reflaxe.ocaml') {
		fail(`unexpected libraries in disposable repository: ${summary.isolation.resolvedLibraries.join(', ')}`)
	}

	const targetPathResult = requireSuccess('installed-target-path', runStep('installed-target-path', haxelibBinary, ['path', 'reflaxe.ocaml'], { env }))
	const installedClasspath = targetPathResult.stdout
		.split('\n')
		.map(line => line.trim())
		.filter(line => line && !line.startsWith('-'))
		.map(line => path.resolve(line))
		.find(line => isInside(isolatedHaxelib, line))
	if (!installedClasspath) {
		fail('reflaxe.ocaml did not resolve from inside the disposable haxelib repository')
	}
	summary.isolation.installedTargetInsideDisposableRepository = true
	summary.isolation.installedTargetRelativePath = path.relative(isolatedHaxelib, installedClasspath).split(path.sep).join('/')

	const doctorResult = requireSuccess('installed-doctor', runStep(
		'installed-doctor',
		haxelibBinary,
		['run', 'reflaxe.ocaml', 'doctor', '--json', '--require', 'native'],
		{cwd: appRoot, env}
	))
	let doctor
	try {
		doctor = JSON.parse(doctorResult.stdout)
	} catch (_) {
		fail('installed reflaxe.ocaml doctor did not return valid JSON')
	}
	Object.assign(summary.tooling, validateInstalledDoctor(doctor, packageMetadata.version))

	const scaffoldRoot = path.join(tempRoot, 'scaffold-app')
	const scaffold = requireSuccess('installed-scaffold-app', runStep(
		'installed-scaffold-app',
		haxelibBinary,
		['run', 'reflaxe.ocaml', 'new', 'app', scaffoldRoot, '--name', 'Installed Scaffold'],
		{cwd: appRoot, env}
	))
	if (!scaffold.stdout.includes('REFLAXE_OCAML_SCAFFOLD:PASS kind=app')) {
		fail('installed reflaxe.ocaml scaffold command did not emit its success marker')
	}
	summary.tooling.scaffoldCommandPassed = true
	const scaffoldBuild = requireSuccess('installed-scaffold-build', runStep(
		'installed-scaffold-build',
		haxelibBinary,
		[
			'run', 'reflaxe.ocaml', 'build', '--project', scaffoldRoot,
			'--run', '.out.reflaxe-ocaml-dune-build/default/out.exe'
		],
		{cwd: appRoot, env}
	))
	if (!scaffoldBuild.stdout.includes('Hello from Installed Scaffold via reflaxe.ocaml!')
		|| !scaffoldBuild.stdout.includes('REFLAXE_OCAML_RUN:PASS')) {
		fail('installed scaffold did not build and execute with its documented output')
	}
	summary.tooling.scaffoldApplicationPassed = true
	const scaffoldInspection = requireSuccess('installed-scaffold-inspect', runStep(
		'installed-scaffold-inspect',
		haxelibBinary,
		[
			'run', 'reflaxe.ocaml', 'inspect', '--project', scaffoldRoot,
			'--output', 'out', '--require-lowering', '--json'
		],
		{cwd: appRoot, env}
	))
	let scaffoldInspectionReport
	try {
		scaffoldInspectionReport = JSON.parse(scaffoldInspection.stdout)
	} catch (error) {
		fail(`installed inspect command did not emit valid JSON: ${error instanceof Error ? error.message : String(error)}`)
	}
	if (scaffoldInspectionReport.schemaVersion !== 41
		|| scaffoldInspectionReport.summary?.valid !== true
		|| scaffoldInspectionReport.generatedFiles?.status !== 'present'
		|| scaffoldInspectionReport.artifactManifest?.status !== 'present'
		|| scaffoldInspectionReport.artifactManifest?.completeForSourceBundle !== true
		|| scaffoldInspectionReport.artifactManifest?.blockers?.length !== 0
		|| scaffoldInspectionReport.buildTiming?.status !== 'present'
		|| scaffoldInspectionReport.buildTiming?.nativeBuildRan !== true
		|| !Number.isInteger(scaffoldInspectionReport.buildTiming?.duneBuildMilliseconds)
		|| scaffoldInspectionReport.buildTiming?.duneCacheHitsMeasured !== false
		|| scaffoldInspectionReport.profile?.status !== 'present'
		|| scaffoldInspectionReport.runtime?.semanticManifest !== false
		|| scaffoldInspectionReport.lowering?.status !== 'present'
		|| scaffoldInspectionReport.representation?.status !== 'present'
		|| scaffoldInspectionReport.representation?.scope !== 'exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15'
		|| !Number.isInteger(scaffoldInspectionReport.summary?.representationDecisionCount)
		|| scaffoldInspectionReport.summary.representationDecisionCount < 1
		|| !scaffoldInspectionReport.representation.decisions?.some(decision =>
			decision.id === 'representation:Int:static-field'
			&& decision.carrierTypeId === 'int'
			&& decision.implicitDefaultPolicy === 'exact-int-zero')
		|| !Number.isInteger(scaffoldInspectionReport.summary?.staticStorageCount)
		|| scaffoldInspectionReport.summary.staticStorageCount < 1
		|| !Array.isArray(scaffoldInspectionReport.lowering?.staticStorage)
		|| scaffoldInspectionReport.lowering.staticStorage.length !== scaffoldInspectionReport.summary.staticStorageCount
		|| typeof scaffoldInspectionReport.lowering?.staticStorageRevision !== 'string'
		|| scaffoldInspectionReport.unavailable?.some(capability => capability.id === 'program-representation')
		|| !scaffoldInspectionReport.unavailable?.some(capability => capability.id === 'export-abi')) {
		fail('installed inspect command did not preserve its compiler-owned authority and deferral contract')
	}
	summary.tooling.inspectCommandPassed = true
	summary.tooling.timingReportPassed = true
	summary.tooling.nativeDuneBuildMilliseconds = scaffoldInspectionReport.buildTiming.duneBuildMilliseconds

	const scaffoldLibraryRoot = path.join(tempRoot, 'scaffold-library')
	const scaffoldLibrary = requireSuccess('installed-scaffold-library', runStep(
		'installed-scaffold-library',
		haxelibBinary,
		['run', 'reflaxe.ocaml', 'new', 'library', scaffoldLibraryRoot, '--name', 'Installed Library'],
		{cwd: appRoot, env}
	))
	if (!scaffoldLibrary.stdout.includes('REFLAXE_OCAML_SCAFFOLD:PASS kind=library')) {
		fail('installed reflaxe.ocaml library scaffold did not emit its success marker')
	}
	const scaffoldLibraryBuild = requireSuccess('installed-scaffold-library-build', runStep(
		'installed-scaffold-library-build',
		haxelibBinary,
		['run', 'reflaxe.ocaml', 'build', '--project', scaffoldLibraryRoot],
		{cwd: appRoot, env}
	))
	const scaffoldLibraryDune = fs.readFileSync(path.join(scaffoldLibraryRoot, 'out/dune'), 'utf8')
	if (!scaffoldLibraryBuild.stdout.includes('REFLAXE_OCAML_BUILD:PASS')
		|| !scaffoldLibraryDune.includes('(library')
		|| scaffoldLibraryDune.includes('(executable')
		|| !fs.existsSync(path.join(scaffoldLibraryRoot, '.out.reflaxe-ocaml-dune-build/default/out.cmxa'))) {
		fail('installed library scaffold did not produce a library-only native Dune build')
	}
	summary.tooling.scaffoldLibraryPassed = true

	const compile = requireSuccess('external-app-compile', runStep(
		'external-app-compile',
		haxelibBinary,
		['run', 'reflaxe.ocaml', 'build', '--hxml', 'build.hxml'],
		{cwd: appRoot, env}
	))
	if (!compile.stdout.includes('REFLAXE_OCAML_BUILD:PASS')) {
		fail('installed reflaxe.ocaml build command did not emit its success marker')
	}
	summary.tooling.buildCommandPassed = true
	summary.externalApplication.compilePassed = compile.status === 0
	const emittedRoot = path.join(appRoot, 'out')
	const executable = path.join(appRoot, '.out.reflaxe-ocaml-dune-build/default/out.exe')
	if (!fs.existsSync(executable)) {
		fail('native build did not produce .out.reflaxe-ocaml-dune-build/default/out.exe')
	}
	summary.externalApplication.nativeBuildPassed = true
	summary.externalApplication.emittedSourceSha256 = generatedSourceRevision(emittedRoot)
	summary.externalApplication.executableSha256 = sha256File(executable)

	const runtime = requireSuccess('external-app-runtime', runStep('external-app-runtime', executable, [], { cwd: appRoot, env }))
	const expected = normalizeOutput(fs.readFileSync(path.join(appRoot, 'expected.stdout'), 'utf8'))
	summary.externalApplication.runtimePassed = runtime.status === 0
	summary.externalApplication.stdoutMatched = runtime.stdout === expected
	summary.externalApplication.stdoutSha256 = crypto.createHash('sha256').update(runtime.stdout).digest('hex')
	if (!summary.externalApplication.stdoutMatched) {
		fs.writeFileSync(path.join(artifactsRoot, 'external-app-runtime.expected.log'), expected)
		fail('external application stdout did not match expected.stdout')
	}
	return env
}

function writeSummary() {
	fs.writeFileSync(path.join(artifactsRoot, 'summary.json'), JSON.stringify(summary, null, 2) + '\n')
}

function verifyEvidenceLogs() {
	const forbidden = evidenceReplacements.map(([localPath]) => localPath)
	for (const file of walkFiles(artifactsRoot, { skipDirectory: name => name === 'build-a' || name === 'build-b' })) {
		if (!file.relative.endsWith('.log')) {
			continue
		}
		const contents = fs.readFileSync(file.absolute, 'utf8')
		for (const localPath of forbidden) {
			if (contents.includes(localPath)) {
				fail(`machine-local path remained in evidence log ${file.relative}`)
			}
		}
	}
	summary.evidence.machineLocalPathsRedacted = true
}

function main() {
	fs.rmSync(artifactsRoot, { recursive: true, force: true })
	ensureDir(artifactsRoot)
	tempRoot = prepareTempRoot()
	addEvidenceReplacement(tempRoot, '<temp>')
	addEvidenceReplacement(artifactsRoot, '<artifacts>')
	addEvidenceReplacement(repoRoot, '<repo>')
	addEvidenceReplacement(os.homedir(), '<home>')
	evidenceReplacements.sort((left, right) => right[0].length - left[0].length)
	try {
		summary.implementationCommit = requireSuccess('implementation-commit', runStep('implementation-commit', 'git', ['rev-parse', 'HEAD'])).stdout.trim()
		summary.workingTreeDirty = requireSuccess('working-tree-status', runStep('working-tree-status', 'git', ['status', '--porcelain'])).stdout.trim().length > 0
		const reflaxeRoot = resolveReflaxeRoot()
		validateReflaxeFramework(reflaxeRoot)
		const zipPath = preparePackageArtifact()
		const installedEnvironment = proveExternalInstall(zipPath, reflaxeRoot)
		writePerformanceEnvironment(installedEnvironment)
		verifyEvidenceLogs()
		summary.marker = 'RO_PACKAGE_INSTALL_SMOKE:PASS'
		writeSummary()
		console.log(`[reflaxe-ocaml-package-install] archive_sha256=${summary.package.sha256}`)
		console.log(`[reflaxe-ocaml-package-install] emitted_source_sha256=${summary.externalApplication.emittedSourceSha256}`)
		console.log(`[reflaxe-ocaml-package-install] executable_sha256=${summary.externalApplication.executableSha256}`)
		console.log(summary.marker)
	} catch (error) {
		summary.error = sanitizeEvidence(error instanceof Error ? error.message : String(error))
		writeSummary()
		console.error(`[reflaxe-ocaml-package-install] ERROR: ${summary.error}`)
		console.error(`[reflaxe-ocaml-package-install] evidence=${path.relative(repoRoot, artifactsRoot)}`)
		if (process.env.RO_KEEP_TEMP === '1') {
			console.error(`[reflaxe-ocaml-package-install] retained_temp=${tempRoot}`)
		}
		process.exitCode = 1
	} finally {
		if (process.env.RO_KEEP_TEMP !== '1' && !process.env.RO_PACKAGE_INSTALL_RETAIN_ROOT) {
			fs.rmSync(tempRoot, { recursive: true, force: true })
		}
	}
}

if (require.main === module) {
	main()
}

module.exports = { findNekoLibraryDirectories, performanceEnvironment, sha256Directory, validateInstalledDoctor }
