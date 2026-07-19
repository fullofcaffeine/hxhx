/**
 * Prepares trustworthy installed-package performance measurements.
 *
 * This module owns package provenance, disposable workspace isolation, host
 * metadata, and evidence path sanitization. The benchmark runner can therefore
 * focus on compiling and executing scenarios instead of becoming a second
 * package installer or CI receipt parser.
 */
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { loadArtifactManifest, sha256File } = require('../release/reflaxe-ocaml-package-artifact')

function fail(message) {
	throw new Error(message)
}

function normalized(text) {
	return String(text).replace(/\r\n/g, '\n').trim()
}

function readJson(filePath) {
	return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function isInside(parent, child) {
	const relative = path.relative(parent, child)
	return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative))
}

function requireSafeDisposableDirectory(directory, label, repoRoot) {
	const resolved = path.resolve(directory)
	if (resolved === path.parse(resolved).root
		|| resolved === os.homedir()
		|| resolved === os.tmpdir()
		|| isInside(resolved, repoRoot)) {
		fail(`${label} must be a dedicated directory, not a filesystem root or repository ancestor`)
	}
	return resolved
}

function gitOutput(repoRoot, args) {
	const result = cp.spawnSync('git', args, { cwd: repoRoot, encoding: 'utf8', shell: false })
	if (result.status !== 0) {
		fail(`git ${args.join(' ')} failed: ${normalized(result.stderr)}`)
	}
	return normalized(result.stdout)
}

function simpleVersion(command, args, env) {
	const result = cp.spawnSync(command, args, { encoding: 'utf8', env })
	if (result.status !== 0) {
		return 'unknown'
	}
	return normalized(result.stdout || result.stderr) || 'unknown'
}

function haxeVersion(env) {
	for (const args of [['--version'], ['-version']]) {
		const result = cp.spawnSync('haxe', args, { encoding: 'utf8', env })
		if (result.status === 0) {
			const value = normalized(result.stdout || result.stderr)
			if (value) {
				return value
			}
		}
	}
	return 'unknown'
}

function loadExecutionEnvironment(environmentFile) {
	const env = { ...process.env }
	if (!environmentFile) {
		return env
	}
	const allowed = new Set([
		'HAXELIB_PATH',
		'HAXE_STD_PATH',
		'HAXEPATH',
		'NEKOPATH',
		'DYLD_LIBRARY_PATH',
		'LD_LIBRARY_PATH',
		'PATH'
	])
	const overrides = readJson(path.resolve(environmentFile))
	for (const [key, value] of Object.entries(overrides)) {
		if (!allowed.has(key) || typeof value !== 'string' || !value) {
			fail(`invalid private performance environment override ${key}`)
		}
		env[key] = value
	}
	return env
}

/** Keeps only real library directories from haxelib's mixed path/options output. */
function resolvedLibraryPaths(output, cwd) {
	return String(output || '')
		.split(/\r?\n/)
		.map(line => line.trim())
		.filter(line => line && fs.existsSync(path.resolve(cwd, line)))
		.map(line => fs.realpathSync(path.resolve(cwd, line)))
}

/**
 * Validates that platform-report mode measures the exact clean package already
 * proven by the isolated installer. Target resolution must remain outside the
 * checkout so repository development metadata cannot satisfy -lib resolution.
 */
function loadPlatformProof(options, env, repoState) {
	if (options.mode === 'reference-gate') {
		return null
	}
	if (options.mode !== 'platform-report') {
		fail(`unsupported RO_PERF_MODE ${options.mode}`)
	}
	for (const name of ['artifactManifest', 'packageInstallSummary', 'workRoot']) {
		if (!options[name]) {
			fail(`${name} is required in platform-report mode`)
		}
	}
	const manifestPath = path.resolve(options.artifactManifest)
	const installSummaryPath = path.resolve(options.packageInstallSummary)
	const workRoot = path.resolve(options.workRoot)
	if (isInside(options.repoRoot, workRoot)) {
		fail('platform performance workspace must live outside the repository checkout')
	}
	const manifest = loadArtifactManifest(manifestPath)
	const installSummary = readJson(installSummaryPath)
	const manifestSha256 = sha256File(manifestPath)
	if (manifest.schemaVersion !== 1 || manifest.marker !== 'RO_PACKAGE_ARTIFACT:PASS' || manifest.workingTreeDirty !== false) {
		fail('platform performance package manifest is not a clean producer receipt')
	}
	if (repoState.implementationCommit !== manifest.implementationCommit || repoState.workingTreeDirty) {
		fail('platform performance checkout does not match the clean package commit')
	}
	if (installSummary.marker !== 'RO_PACKAGE_INSTALL_SMOKE:PASS' || installSummary.workingTreeDirty !== false) {
		fail('platform performance package installation did not pass from a clean checkout')
	}
	if (installSummary.implementationCommit !== repoState.implementationCommit
		|| installSummary.package.buildMode !== 'supplied'
		|| installSummary.package.producerCommit !== repoState.implementationCommit
		|| installSummary.package.producerWorkingTreeDirty !== false
		|| installSummary.package.artifactManifestSha256 !== manifestSha256) {
		fail('platform performance package installation has different producer provenance')
	}
	for (const field of ['name', 'version', 'archiveFile', 'sha256', 'bytes', 'sourceOnly', 'fileCount', 'reproducible']) {
		if (installSummary.package[field] !== manifest.package[field]) {
			fail(`platform performance package installation disagrees on ${field}`)
		}
	}
	if (!env.HAXELIB_PATH || env.HAXELIB_PATH.includes(path.delimiter)) {
		fail('platform performance requires one disposable HAXELIB_PATH')
	}
	const haxelibRoot = path.resolve(env.HAXELIB_PATH)
	const installedRelativePath = installSummary.isolation && installSummary.isolation.installedTargetRelativePath
	const installedTargetPath = installedRelativePath ? path.resolve(haxelibRoot, installedRelativePath) : null
	if (!installedTargetPath || !isInside(haxelibRoot, installedTargetPath) || !fs.existsSync(installedTargetPath)) {
		fail('platform performance target does not exist inside the disposable haxelib repository')
	}
	if (isInside(options.repoRoot, installedTargetPath)) {
		fail('platform performance target unexpectedly resolves from the repository checkout')
	}
	const resolution = cp.spawnSync('haxelib', ['path', 'reflaxe.ocaml'], {
		cwd: path.dirname(workRoot),
		env,
		encoding: 'utf8',
		shell: false
	})
	if (resolution.status !== 0) {
		fail(`installed reflaxe.ocaml target did not resolve: ${normalized(resolution.stderr)}`)
	}
	const resolvedPaths = resolvedLibraryPaths(resolution.stdout, path.dirname(workRoot))
	const expectedTargetPath = fs.realpathSync(installedTargetPath)
	if (!resolvedPaths.includes(expectedTargetPath) || resolvedPaths.some(resolvedPath => isInside(options.repoRoot, resolvedPath))) {
		fail('haxelib resolved reflaxe.ocaml from somewhere other than the proven disposable installation')
	}
	return {
		manifest,
		manifestSha256,
		installSummary,
		installedRelativePath,
		targetResolvedOutsideCheckout: true,
		workRoot
	}
}

/** Builds the immutable context shared by every performance scenario. */
function createPerformanceContext(options) {
	const repoRoot = path.resolve(options.repoRoot)
	const artifactsDir = requireSafeDisposableDirectory(options.artifactsDir, 'performance artifact directory', repoRoot)
	const env = loadExecutionEnvironment(options.environmentFile)
	const repoState = {
		implementationCommit: gitOutput(repoRoot, ['rev-parse', 'HEAD']),
		workingTreeDirty: gitOutput(repoRoot, ['status', '--porcelain']).length > 0
	}
	const platformProof = loadPlatformProof({ ...options, repoRoot }, env, repoState)
	const workRoot = platformProof
		? requireSafeDisposableDirectory(platformProof.workRoot, 'platform performance workspace', repoRoot)
		: null
	if (workRoot) {
		fs.rmSync(workRoot, { recursive: true, force: true })
		fs.mkdirSync(workRoot, { recursive: true })
	}
	const replacements = [repoRoot, artifactsDir, os.homedir(), workRoot, env.HAXELIB_PATH]
		.filter(Boolean)
		.map(value => path.resolve(value))
		.sort((left, right) => right.length - left.length)
	return {
		repoRoot,
		artifactsDir,
		env,
		repoState,
		workRoot,
		platformProof,
		enforceReferenceThresholds: options.mode === 'reference-gate',
		replacements,
		temporaryRoots: []
	}
}

/**
 * Copies one scenario into disposable storage for benchmarks that must edit it.
 * The directory is registered for both evidence sanitization and final cleanup.
 */
function isolatedScenarioDirectory(scenario, context) {
	const source = path.join(context.repoRoot, scenario.exampleDir)
	let root
	if (context.workRoot) {
		root = context.workRoot
	} else {
		// Local Lix metadata is discovered by walking up to the checkout's
		// haxe_libraries directory, so keep the disposable copy under the repo.
		// Hosted package runs still use the external proven workRoot above.
		const localTemp = path.join(context.repoRoot, '.tmp')
		fs.mkdirSync(localTemp, { recursive: true })
		root = fs.mkdtempSync(path.join(localTemp, 'reflaxe-ocaml-perf-'))
		context.temporaryRoots.push(root)
		for (const replacement of new Set([path.resolve(root), fs.realpathSync(root)])) {
			context.replacements.push(replacement)
		}
		context.replacements.sort((left, right) => right.length - left.length)
	}
	const destination = path.join(root, scenario.id)
	fs.rmSync(destination, { recursive: true, force: true })
	fs.cpSync(source, destination, { recursive: true })
	return destination
}

function environmentSummary(context) {
	const cpus = os.cpus()
	const runnerImage = {}
	for (const [field, environmentName] of [
		['runnerOs', 'RUNNER_OS'],
		['runnerArch', 'RUNNER_ARCH'],
		['imageOs', 'ImageOS'],
		['imageVersion', 'ImageVersion'],
		['githubRunId', 'GITHUB_RUN_ID'],
		['githubRunAttempt', 'GITHUB_RUN_ATTEMPT']
	]) {
		if (process.env[environmentName]) {
			runnerImage[field] = process.env[environmentName]
		}
	}
	return {
		platform: process.platform,
		architecture: process.arch,
		cpu: {
			count: cpus.length,
			model: cpus.length ? cpus[0].model : 'unknown'
		},
		loadAverage: os.loadavg(),
		totalMemoryBytes: os.totalmem(),
		runnerImage,
		toolchain: {
			haxe: haxeVersion(context.env),
			haxelib: simpleVersion('haxelib', ['version'], context.env),
			dune: simpleVersion('dune', ['--version'], context.env),
			ocamlc: simpleVersion('ocamlc', ['-version'], context.env),
			node: process.version
		}
	}
}

function provenanceSummary(context) {
	const proof = context.platformProof
	if (!proof) {
		return {
			...context.repoState,
			installedPackageProof: false
		}
	}
	const packageInfo = proof.manifest.package
	return {
		...context.repoState,
		installedPackageProof: true,
		artifactManifestSha256: proof.manifestSha256,
		package: {
			name: packageInfo.name,
			version: packageInfo.version,
			archiveFile: packageInfo.archiveFile,
			sha256: packageInfo.sha256,
			bytes: packageInfo.bytes,
			sourceOnly: packageInfo.sourceOnly,
			fileCount: packageInfo.fileCount,
			reproducible: packageInfo.reproducible
		},
		installation: {
			buildMode: proof.installSummary.package.buildMode,
			platform: proof.installSummary.platform,
			architecture: proof.installSummary.architecture,
			toolchain: proof.installSummary.toolchain,
			installedTargetRelativePath: proof.installedRelativePath,
			targetResolvedOutsideCheckout: proof.targetResolvedOutsideCheckout,
			isolationSmokePassed: proof.installSummary.marker === 'RO_PACKAGE_INSTALL_SMOKE:PASS'
		}
	}
}

function sanitizeText(value, context) {
	let sanitized = String(value || '')
	for (const localPath of context.replacements) {
		sanitized = sanitized.split(localPath).join('<local>')
	}
	return sanitized
}

function scenarioDirectory(scenario, context) {
	const source = path.join(context.repoRoot, scenario.exampleDir)
	if (!context.workRoot) {
		return source
	}
	const destination = path.join(context.workRoot, scenario.id)
	fs.rmSync(destination, { recursive: true, force: true })
	fs.cpSync(source, destination, { recursive: true })
	return destination
}

function verifyEvidenceSanitized(context) {
	const stack = [context.artifactsDir]
	while (stack.length) {
		const current = stack.pop()
		for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
			const filePath = path.join(current, entry.name)
			if (entry.isDirectory()) {
				stack.push(filePath)
				continue
			}
			const contents = fs.readFileSync(filePath, 'utf8')
			for (const localPath of context.replacements) {
				if (contents.includes(localPath)) {
					fail(`performance evidence contains an unsanitized machine-local path in ${entry.name}`)
				}
			}
		}
	}
}

/** Removes only the external scenario workspace, never the installed package. */
function cleanupPerformanceContext(context) {
	for (const root of context.temporaryRoots || []) {
		fs.rmSync(root, { recursive: true, force: true })
	}
	if (context.workRoot && process.env.RO_PERF_KEEP_WORK !== '1') {
		fs.rmSync(context.workRoot, { recursive: true, force: true })
	}
}

module.exports = {
	cleanupPerformanceContext,
	createPerformanceContext,
	environmentSummary,
	isolatedScenarioDirectory,
	provenanceSummary,
	resolvedLibraryPaths,
	sanitizeText,
	scenarioDirectory,
	verifyEvidenceSanitized
}
