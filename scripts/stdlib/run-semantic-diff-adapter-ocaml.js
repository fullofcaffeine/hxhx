#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

function fail(message) {
	console.error(`[semantic-diff] ERROR: ${message}`)
	process.exit(1)
}

function parseBool(value, label) {
	if (value === '1' || value === 'true') {
		return true
	}
	if (value === '0' || value === 'false') {
		return false
	}
	fail(`${label} must be one of: true,false,1,0 (received: ${value})`)
}

function parseArgs(argv) {
	const options = {
		manifestPath: 'test/portable/semantic_diff/corpus_v1.json',
		sliceId: 'core_seed_v1',
		fixturesCsv: null,
		strictNativeSurface: true,
		adapterId: 'ocaml',
		outPath: null,
		printJson: true,
	}

	for (let index = 2; index < argv.length; index += 1) {
		const arg = argv[index]
		if (arg === '--manifest') {
			options.manifestPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--slice') {
			options.sliceId = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--fixtures') {
			options.fixturesCsv = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--strict-native-surface') {
			options.strictNativeSurface = parseBool(argv[index + 1], '--strict-native-surface')
			index += 1
			continue
		}
		if (arg === '--adapter-id') {
			options.adapterId = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--out') {
			options.outPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--no-print-json') {
			options.printJson = false
			continue
		}
		fail(`unknown argument: ${arg}`)
	}

	if (options.adapterId.length === 0) {
		fail('--adapter-id must not be empty')
	}
	return options
}

function readJson(filePath) {
	try {
		return JSON.parse(fs.readFileSync(filePath, 'utf8'))
	} catch (error) {
		fail(`invalid json at ${filePath}: ${error}`)
	}
}

function normalizeOutput(value) {
	const input = typeof value === 'string' ? value : ''
	const normalizedNewlines = input.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
	const normalizedLines = normalizedNewlines.split('\n').map((line) => line.replace(/[ \t]+$/u, ''))
	while (normalizedLines.length > 0 && normalizedLines[normalizedLines.length - 1] === '') {
		normalizedLines.pop()
	}
	return normalizedLines.join('\n')
}

function normalizeFixtureList(fixturesCsv) {
	const fixtureIds = []
	for (const rawValue of fixturesCsv.split(',')) {
		const fixtureId = rawValue.trim()
		if (fixtureId.length === 0) {
			continue
		}
		fixtureIds.push(fixtureId)
	}
	if (fixtureIds.length === 0) {
		fail('--fixtures resolved to empty fixture list')
	}
	return fixtureIds
}

function listSliceFixtures(corpusManifest, sliceId) {
	if (!Array.isArray(corpusManifest.slices)) {
		fail('corpus manifest must contain slices array')
	}
	const slice = corpusManifest.slices.find((value) => value.id === sliceId)
	if (slice == null) {
		fail(`missing semantic-diff slice: ${sliceId}`)
	}
	if (!Array.isArray(slice.fixtures) || slice.fixtures.length === 0) {
		fail(`semantic-diff slice has no fixtures: ${sliceId}`)
	}
	return normalizeFixtureList(slice.fixtures.join(','))
}

function hasExecutable(name) {
	const result = spawnSync('bash', ['-lc', `command -v ${name}`], {
		encoding: 'utf8',
	})
	return result.status === 0
}

function runCommand(command, args, options) {
	const result = spawnSync(command, args, {
		...options,
		encoding: 'utf8',
		maxBuffer: 1024 * 1024 * 20,
	})
	const stdout = normalizeOutput(result.stdout)
	const stderr = normalizeOutput(result.stderr)
	if (result.error != null) {
		return {
			ok: false,
			statusCode: result.status ?? 1,
			stdout,
			stderr: normalizeOutput(`${stderr}\n${String(result.error.message)}`),
		}
	}
	return {
		ok: result.status === 0,
		statusCode: result.status ?? 1,
		stdout,
		stderr,
	}
}

function ensureFixtureDirectory(rootPath, fixtureId) {
	const fixtureDir = path.join(rootPath, fixtureId)
	const buildHxml = path.join(fixtureDir, 'build.hxml')
	if (!fs.existsSync(fixtureDir) || !fs.statSync(fixtureDir).isDirectory()) {
		return { ok: false, reason: `missing fixture directory: ${fixtureId}` }
	}
	if (!fs.existsSync(buildHxml)) {
		return { ok: false, reason: `missing build.hxml: ${fixtureId}` }
	}
	return { ok: true, fixtureDir }
}

function fixtureReplayCommand(strictNativeSurface, fixtureId) {
	const strictValue = strictNativeSurface ? '1' : '0'
	return `PORTABLE_NATIVE_SURFACE_STRICT=${strictValue} PORTABLE_FIXTURE_ALLOWLIST=${fixtureId} bash scripts/test-portable.sh`
}

function buildSummaryCounters(fixtures) {
	const counters = {
		total: fixtures.length,
		ok: 0,
		compileError: 0,
		runtimeError: 0,
		fixtureError: 0,
		skipToolchain: 0,
	}
	for (const fixture of fixtures) {
		if (fixture.status === 'ok') {
			counters.ok += 1
		} else if (fixture.status === 'compile_error') {
			counters.compileError += 1
		} else if (fixture.status === 'runtime_error') {
			counters.runtimeError += 1
		} else if (fixture.status === 'fixture_error') {
			counters.fixtureError += 1
		} else if (fixture.status === 'skip_toolchain') {
			counters.skipToolchain += 1
		}
	}
	return counters
}

function runFixtureReport({
	repoRoot,
	fixtureRoot,
	fixtureIds,
	haxeBin,
	strictNativeSurface,
}) {
	const fixtureReports = []

	if (!hasExecutable('dune') || !hasExecutable('ocamlc')) {
		for (const fixtureId of fixtureIds) {
			fixtureReports.push({
				fixtureId,
				status: 'skip_toolchain',
				compileExitCode: null,
				runExitCode: null,
				stdout: '',
				stderr: 'Skipping fixture: dune/ocamlc not found on PATH.',
				replayCommand: fixtureReplayCommand(strictNativeSurface, fixtureId),
			})
		}
		return fixtureReports
	}

	for (const fixtureId of fixtureIds) {
		const fixtureCheck = ensureFixtureDirectory(fixtureRoot, fixtureId)
		if (!fixtureCheck.ok) {
			fixtureReports.push({
				fixtureId,
				status: 'fixture_error',
				compileExitCode: null,
				runExitCode: null,
				stdout: '',
				stderr: fixtureCheck.reason,
				replayCommand: fixtureReplayCommand(strictNativeSurface, fixtureId),
			})
			continue
		}

		const compileArgs = ['build.hxml', '-D', 'ocaml_build=native']
		if (strictNativeSurface) {
			compileArgs.push('-D', 'ocaml_portable_native_surface=error')
		}
		const compileResult = runCommand(haxeBin, compileArgs, { cwd: fixtureCheck.fixtureDir })
		if (!compileResult.ok) {
			fixtureReports.push({
				fixtureId,
				status: 'compile_error',
				compileExitCode: compileResult.statusCode,
				runExitCode: null,
				stdout: compileResult.stdout,
				stderr: compileResult.stderr,
				replayCommand: fixtureReplayCommand(strictNativeSurface, fixtureId),
			})
			continue
		}

		const executablePath = path.join(fixtureCheck.fixtureDir, 'out', '_build', 'default', 'out.exe')
		if (!fs.existsSync(executablePath)) {
			fixtureReports.push({
				fixtureId,
				status: 'fixture_error',
				compileExitCode: compileResult.statusCode,
				runExitCode: null,
				stdout: compileResult.stdout,
				stderr: 'Missing built executable: out/_build/default/out.exe',
				replayCommand: fixtureReplayCommand(strictNativeSurface, fixtureId),
			})
			continue
		}

		const stdinPath = path.join(fixtureCheck.fixtureDir, 'stdin.txt')
		const runInput = fs.existsSync(stdinPath) ? fs.readFileSync(stdinPath, 'utf8') : undefined
		const runEnv = { ...process.env, HX_TEST_ENV: 'ok' }
		delete runEnv.HX_TEST_ENV_MISSING_REFLAXE_OCAML
		const runResult = runCommand(executablePath, [], {
			cwd: fixtureCheck.fixtureDir,
			input: runInput,
			env: runEnv,
		})

		fixtureReports.push({
			fixtureId,
			status: runResult.ok ? 'ok' : 'runtime_error',
			compileExitCode: compileResult.statusCode,
			runExitCode: runResult.statusCode,
			stdout: runResult.stdout,
			stderr: runResult.stderr,
			replayCommand: fixtureReplayCommand(strictNativeSurface, fixtureId),
		})
	}
	return fixtureReports
}

function writeJson(filePath, payload) {
	const absolutePath = path.resolve(filePath)
	fs.mkdirSync(path.dirname(absolutePath), { recursive: true })
	fs.writeFileSync(absolutePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8')
}

function main() {
	const options = parseArgs(process.argv)
	const repoRoot = path.resolve(__dirname, '..', '..')
	const manifestPath = path.resolve(repoRoot, options.manifestPath)
	const corpusManifest = readJson(manifestPath)
	const fixtureIds =
		options.fixturesCsv != null ? normalizeFixtureList(options.fixturesCsv) : listSliceFixtures(corpusManifest, options.sliceId)
	const fixtureRoot = path.resolve(repoRoot, corpusManifest.fixtureRoot ?? 'test/portable/fixtures')
	const haxeBin = process.env.HAXE_BIN ?? 'haxe'
	const report = {
		schemaVersion: 1,
		contractId: 'reflaxe.family.std.adapter_observable_report',
		contractVersion: '1.0.0',
		adapterId: options.adapterId,
		sliceId: options.sliceId,
		manifestRef: path.relative(repoRoot, manifestPath).split(path.sep).join('/'),
		fixtureRoot: path.relative(repoRoot, fixtureRoot).split(path.sep).join('/'),
		strictNativeSurface: options.strictNativeSurface,
		replayTemplate: `PORTABLE_NATIVE_SURFACE_STRICT=${options.strictNativeSurface ? '1' : '0'} PORTABLE_FIXTURE_ALLOWLIST=<fixtureId> bash scripts/test-portable.sh`,
		fixtures: runFixtureReport({
			repoRoot,
			fixtureRoot,
			fixtureIds,
			haxeBin,
			strictNativeSurface: options.strictNativeSurface,
		}),
	}
	report.summary = buildSummaryCounters(report.fixtures)

	if (options.outPath != null) {
		writeJson(path.resolve(repoRoot, options.outPath), report)
		console.log(
			`[semantic-diff] WROTE_ADAPTER_REPORT path=${options.outPath} adapter=${report.adapterId} fixtures=${report.summary.total}`
		)
	}
	if (options.printJson) {
		process.stdout.write(`${JSON.stringify(report, null, 2)}\n`)
	}
}

main()
