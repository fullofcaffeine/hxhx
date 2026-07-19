#!/usr/bin/env node
/**
 * Measures the standalone reflaxe.ocaml edit loop without mutating tracked input.
 *
 * The workload copies one repo-owned example, then runs ordered cold-output,
 * unchanged-output, and changed-one-file builds. Target-owned timing comes from
 * the compiler report; this runner owns only the full child-process boundary,
 * isolated source edit, executable verification, and raw-sample aggregation.
 */
const cp = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const { isolatedScenarioDirectory, sanitizeText } = require('./reflaxe-ocaml-perf-platform')

const STATE_ORDER = ['cold-output', 'warm-unchanged', 'one-file-change']

function fail(message) {
	throw new Error(message)
}

function ensureDir(directory) {
	fs.mkdirSync(directory, { recursive: true })
}

function normalized(value) {
	return String(value || '').replace(/\r\n/g, '\n').trim()
}

function sha256(value) {
	return crypto.createHash('sha256').update(value).digest('hex')
}

function run(command, args, options) {
	const started = process.hrtime.bigint()
	const result = cp.spawnSync(command, args, {
		cwd: options.cwd,
		env: options.env,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
	const durationMilliseconds = Number((process.hrtime.bigint() - started) / 1000000n)
	return {
		status: result.status == null ? 1 : result.status,
		stdout: result.stdout || '',
		stderr: result.stderr || '',
		durationMilliseconds
	}
}

function writeLogs(directory, prefix, result, context) {
	fs.writeFileSync(path.join(directory, `${prefix}.stdout.log`), sanitizeText(result.stdout, context))
	fs.writeFileSync(path.join(directory, `${prefix}.stderr.log`), sanitizeText(result.stderr, context))
}

function replaceExactlyOnce(contents, before, after, label) {
	const first = contents.indexOf(before)
	if (first < 0 || contents.indexOf(before, first + before.length) >= 0) {
		fail(`${label} must contain exactly one controlled change marker`)
	}
	return contents.slice(0, first) + after + contents.slice(first + before.length)
}

function snapshotFiles(root, include) {
	const result = new Map()
	if (!fs.existsSync(root)) {
		return result
	}
	function visit(directory) {
		for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
			if (entry.name === '_build') {
				continue
			}
			const absolute = path.join(directory, entry.name)
			if (entry.isDirectory()) {
				visit(absolute)
			} else if (entry.isFile()) {
				const relative = path.relative(root, absolute).split(path.sep).join('/')
				if (include(relative)) {
					result.set(relative, sha256(fs.readFileSync(absolute)))
				}
			} else {
				fail(`unexpected non-file benchmark input: ${path.relative(root, absolute)}`)
			}
		}
	}
	visit(root)
	return result
}

function changedFiles(before, after) {
	const names = new Set([...before.keys(), ...after.keys()])
	return [...names].filter(name => before.get(name) !== after.get(name)).sort()
}

function generatedSnapshot(workDirectory, outputDirectory) {
	return snapshotFiles(path.join(workDirectory, outputDirectory), relative => relative.endsWith('.ml') || relative.endsWith('.mli'))
}

function haxeSourceSnapshot(workDirectory) {
	return snapshotFiles(workDirectory, relative => relative.endsWith('.hx'))
}

function readJson(filePath, label) {
	try {
		return JSON.parse(fs.readFileSync(filePath, 'utf8'))
	} catch (error) {
		fail(`${label} could not read ${path.basename(filePath)}: ${error instanceof Error ? error.message : String(error)}`)
	}
}

function readTargetTiming(workDirectory, outputDirectory, label) {
	const root = path.join(workDirectory, outputDirectory)
	const generated = readJson(path.join(root, '_GeneratedFiles.json'), label)
	const timing = readJson(path.join(root, 'ocaml_build_timing_report.json'), label)
	if (generated.version !== 1 || !Number.isInteger(generated.id) || generated.id < 0
		|| timing.schemaVersion !== 1 || timing.generatedFilesReceiptId !== generated.id
		|| timing.mode !== 'native' || timing.duneLayout !== 'executable' || timing.target !== './out.exe'
		|| timing.summary?.status !== 'passed' || timing.summary.exitCode !== 0 || timing.summary.nativeBuildRan !== true
		|| !Number.isInteger(timing.summary.duneBuildMilliseconds) || timing.summary.duneBuildMilliseconds < 0
		|| !Number.isInteger(timing.summary.interfaceMilliseconds) || timing.summary.interfaceMilliseconds < 0
		|| timing.summary.targetRunMilliseconds !== null
		|| timing.boundaries?.duneCacheHitsMeasured !== false || timing.boundaries.loadSeparated !== false
		|| timing.boundaries.startupSeparated !== false || timing.boundaries.workloadRuntimeSeparated !== false
		|| JSON.stringify(timing.boundaries.duneBuildIncludes) !== JSON.stringify(['typecheck', 'compile', 'link'])
		|| !Array.isArray(timing.phases) || timing.phases.length === 0 || timing.phases.some(phase => typeof phase.id !== 'string'
			|| !Number.isInteger(phase.elapsedMilliseconds) || phase.elapsedMilliseconds < 0 || phase.exitCode !== 0)) {
		fail(`${label} did not contain a passed, receipt-linked, honestly bounded native timing report`)
	}
	let targetTotal = 0
	let duneTotal = 0
	let interfaceTotal = 0
	const phaseIds = new Set()
	for (const phase of timing.phases) {
		if (phaseIds.has(phase.id)) {
			fail(`${label} timing report contains duplicate phase ${phase.id}`)
		}
		phaseIds.add(phase.id)
		targetTotal += phase.elapsedMilliseconds
		if (phase.id === 'dune_build' || phase.id === 'mli_rebuild') {
			duneTotal += phase.elapsedMilliseconds
		} else if (phase.id.startsWith('mli_')) {
			interfaceTotal += phase.elapsedMilliseconds
		}
	}
	if (duneTotal !== timing.summary.duneBuildMilliseconds || interfaceTotal !== timing.summary.interfaceMilliseconds) {
		fail(`${label} timing summary disagrees with its recorded target phases`)
	}
	return {
		generatedFilesReceiptId: timing.generatedFilesReceiptId,
		duneBuildMilliseconds: timing.summary.duneBuildMilliseconds,
		interfaceMilliseconds: timing.summary.interfaceMilliseconds,
		targetRunMilliseconds: timing.summary.targetRunMilliseconds,
		phases: timing.phases,
		targetSubprocessMilliseconds: targetTotal,
		duneBuildIncludes: timing.boundaries.duneBuildIncludes,
		duneCacheHitsMeasured: timing.boundaries.duneCacheHitsMeasured,
		loadSeparated: timing.boundaries.loadSeparated,
		startupSeparated: timing.boundaries.startupSeparated,
		workloadRuntimeSeparated: timing.boundaries.workloadRuntimeSeparated
	}
}

function verifyExecutable(scenario, workDirectory, expectedStdout, prefix, logDirectory, context) {
	const executable = path.join(workDirectory, scenario.executableRelativePath)
	if (!fs.existsSync(executable) || fs.statSync(executable).isDirectory()) {
		fail(`${prefix} did not produce ${scenario.executableRelativePath}`)
	}
	const result = run(executable, [], { cwd: workDirectory, env: context.env })
	writeLogs(logDirectory, `${prefix}-run`, result, context)
	const actual = normalized(result.stdout)
	const expected = normalized(expectedStdout)
	if (result.status !== 0 || actual !== expected) {
		fail(`${prefix} native executable failed or produced unexpected output`)
	}
	return {
		status: result.status,
		durationMilliseconds: result.durationMilliseconds,
		expectedStdoutSha256: sha256(expected),
		actualStdoutSha256: sha256(actual)
	}
}

function measureState(options) {
	const {
		scenario,
		context,
		workDirectory,
		logDirectory,
		cycle,
		warmup,
		state,
		expectedStdout,
		previousGenerated,
		sourceFilesChanged
	} = options
	const prefix = `${warmup ? 'warmup' : 'measured'}-${cycle}-${state}`
	const build = run('haxe', scenario.compileArgs, { cwd: workDirectory, env: context.env })
	writeLogs(logDirectory, `${prefix}-build`, build, context)
	if (build.status !== 0) {
		fail(`${prefix} Haxe build failed with exit ${build.status}`)
	}

	const timing = readTargetTiming(workDirectory, scenario.outDir, prefix)
	const targetSubprocessMilliseconds = timing.targetSubprocessMilliseconds
	if (targetSubprocessMilliseconds > build.durationMilliseconds) {
		fail(`${prefix} target subprocess total exceeded the full Haxe child duration`)
	}
	const generated = generatedSnapshot(workDirectory, scenario.outDir)
	const generatedCodeChangedFiles = changedFiles(previousGenerated, generated)
	const verification = verifyExecutable(scenario, workDirectory, expectedStdout, prefix, logDirectory, context)

	return {
		generated,
		sample: {
			cycle,
			warmup,
			state,
			outputState: state === 'cold-output' ? 'removed-before-build' : 'preserved-from-prior-state',
			sourceFilesChanged,
			generatedCodeChangedFiles,
			generatedCodeFileCount: generated.size,
			generatedFilesReceiptId: timing.generatedFilesReceiptId,
			compileStatus: build.status,
			timingReportValidationPassed: true,
			verificationStatus: verification.status,
			fullHaxeChildMilliseconds: build.durationMilliseconds,
			targetSubprocessMilliseconds,
			outsideTargetSubprocessMilliseconds: build.durationMilliseconds - targetSubprocessMilliseconds,
			duneBuildMilliseconds: timing.duneBuildMilliseconds,
			interfaceMilliseconds: timing.interfaceMilliseconds,
			targetRunMilliseconds: timing.targetRunMilliseconds,
			externalVerificationMilliseconds: verification.durationMilliseconds,
			timingPhases: timing.phases,
			duneBuildIncludes: timing.duneBuildIncludes,
			duneCacheHitsMeasured: timing.duneCacheHitsMeasured,
			loadSeparated: timing.loadSeparated,
			startupSeparated: timing.startupSeparated,
			workloadRuntimeSeparated: timing.workloadRuntimeSeparated,
			expectedStdoutSha256: verification.expectedStdoutSha256,
			actualStdoutSha256: verification.actualStdoutSha256
		}
	}
}

function measureCycle(options) {
	const { scenario, context, workDirectory, logDirectory, cycle, warmup, originalSource, changedSource, expectedBefore, expectedAfter } = options
	const sourcePath = path.join(workDirectory, scenario.sourceChange.relativePath)
	fs.writeFileSync(sourcePath, originalSource)
	fs.rmSync(path.join(workDirectory, scenario.outDir), { recursive: true, force: true })

	const cold = measureState({
		scenario,
		context,
		workDirectory,
		logDirectory,
		cycle,
		warmup,
		state: 'cold-output',
		expectedStdout: expectedBefore,
		previousGenerated: new Map(),
		sourceFilesChanged: []
	})
	const warm = measureState({
		scenario,
		context,
		workDirectory,
		logDirectory,
		cycle,
		warmup,
		state: 'warm-unchanged',
		expectedStdout: expectedBefore,
		previousGenerated: cold.generated,
		sourceFilesChanged: []
	})

	fs.writeFileSync(sourcePath, changedSource)
	const oneFileSources = changedFiles(options.originalSourceSnapshot, haxeSourceSnapshot(workDirectory))
	if (JSON.stringify(oneFileSources) !== JSON.stringify([scenario.sourceChange.relativePath])) {
		fail(`one-file state changed unexpected Haxe sources: ${oneFileSources.join(', ')}`)
	}
	const oneFile = measureState({
		scenario,
		context,
		workDirectory,
		logDirectory,
		cycle,
		warmup,
		state: 'one-file-change',
		expectedStdout: expectedAfter,
		previousGenerated: warm.generated,
		sourceFilesChanged: oneFileSources
	})

	if (cold.sample.generatedCodeChangedFiles.length === 0) {
		fail('cold-output state produced no generated OCaml source')
	}
	if (warm.sample.generatedCodeChangedFiles.length !== 0) {
		fail(`warm-unchanged state changed generated OCaml: ${warm.sample.generatedCodeChangedFiles.join(', ')}`)
	}
	if (oneFile.sample.generatedCodeChangedFiles.length === 0) {
		fail('one-file state did not change generated OCaml source')
	}

	fs.writeFileSync(sourcePath, originalSource)
	return [cold.sample, warm.sample, oneFile.sample]
}

function stateMeasurements(samples, stats) {
	const result = {}
	for (const [key, state] of [['cold', 'cold-output'], ['warm', 'warm-unchanged'], ['oneFile', 'one-file-change']]) {
		const selected = samples.filter(sample => sample.state === state)
		result[key] = {
			fullHaxeChild: stats(selected.map(sample => sample.fullHaxeChildMilliseconds)),
			targetSubprocess: stats(selected.map(sample => sample.targetSubprocessMilliseconds)),
			outsideTargetSubprocess: stats(selected.map(sample => sample.outsideTargetSubprocessMilliseconds)),
			duneBuild: stats(selected.map(sample => sample.duneBuildMilliseconds)),
			interface: stats(selected.map(sample => sample.interfaceMilliseconds)),
			externalVerification: stats(selected.map(sample => sample.externalVerificationMilliseconds))
		}
	}
	return result
}

/** Runs one report-only iteration workload and returns its self-describing receipt. */
function measureIterationScenario(scenario, context, stats, artifactsDirectory) {
	if (!scenario || scenario.kind !== 'authoring_iteration' || !STATE_ORDER.every((state, index) => scenario.stateOrder?.[index] === state)
		|| scenario.stateOrder.length !== STATE_ORDER.length || !Number.isInteger(scenario.warmupCycles) || scenario.warmupCycles < 1
		|| !Number.isInteger(scenario.measuredCycles) || scenario.measuredCycles < 1
		|| !scenario.compileArgs.includes('ocaml_build_timing_report')) {
		fail('iteration scenario configuration is incomplete or does not request target-owned timing')
	}

	const workDirectory = isolatedScenarioDirectory(scenario, context)
	const logDirectory = path.join(artifactsDirectory, scenario.id)
	ensureDir(logDirectory)
	const sourcePath = path.join(workDirectory, scenario.sourceChange.relativePath)
	const expectedPath = path.join(workDirectory, 'expected.stdout')
	if (!fs.existsSync(sourcePath) || !fs.existsSync(expectedPath)) {
		fail('iteration fixture is missing its controlled source or expected.stdout')
	}
	const originalSource = fs.readFileSync(sourcePath, 'utf8')
	const expectedBefore = fs.readFileSync(expectedPath, 'utf8')
	const changedSource = replaceExactlyOnce(originalSource, scenario.sourceChange.before, scenario.sourceChange.after, scenario.sourceChange.relativePath)
	const expectedAfter = replaceExactlyOnce(expectedBefore, scenario.expectedOutputChange.before, scenario.expectedOutputChange.after, 'expected.stdout')
	const originalSourceSnapshot = haxeSourceSnapshot(workDirectory)
	const warmupSamples = []
	const samples = []

	try {
		for (let cycle = 1; cycle <= scenario.warmupCycles; cycle += 1) {
			warmupSamples.push(...measureCycle({
				scenario,
				context,
				workDirectory,
				logDirectory,
				cycle,
				warmup: true,
				originalSource,
				changedSource,
				expectedBefore,
				expectedAfter,
				originalSourceSnapshot
			}))
		}
		for (let cycle = 1; cycle <= scenario.measuredCycles; cycle += 1) {
			samples.push(...measureCycle({
				scenario,
				context,
				workDirectory,
				logDirectory,
				cycle,
				warmup: false,
				originalSource,
				changedSource,
				expectedBefore,
				expectedAfter,
				originalSourceSnapshot
			}))
		}
	} finally {
		fs.writeFileSync(sourcePath, originalSource)
	}

	const restoredSources = changedFiles(originalSourceSnapshot, haxeSourceSnapshot(workDirectory))
	if (restoredSources.length !== 0) {
		fail(`iteration fixture was not restored: ${restoredSources.join(', ')}`)
	}
	return {
		id: scenario.id,
		kind: scenario.kind,
		title: scenario.title,
		owner: {
			measurementBead: 'haxe_ocaml-850ii.21',
			workflowBead: 'haxe_ocaml-1hd2w'
		},
		method: {
			stateOrder: STATE_ORDER,
			warmupCycles: scenario.warmupCycles,
			measuredCycles: scenario.measuredCycles,
			thresholdMode: 'report-only-until-stable-hosted-trend',
			outputDirectoryRemovedOnlyBeforeCold: true,
			sharedToolchainCachesMayRemainWarm: true,
			cacheHitsInferred: false,
			trackedSourcesMutated: false,
			fullHaxeChildIncludes: ['startup', 'typing', 'generation', 'orchestration', 'target-owned-subprocesses'],
			duneBuildIncludes: ['typecheck', 'compile', 'link'],
			loadSeparated: false,
			startupSeparated: false,
			workloadRuntimeSeparated: false
		},
		command: {
			executable: 'haxe',
			args: scenario.compileArgs
		},
		fixture: {
			exampleDir: scenario.exampleDir,
			sourceFile: scenario.sourceChange.relativePath,
			sourceFilesChangedPerOneFileState: 1,
			sourceRestored: true
		},
		warmupSamples,
		samples,
		measurements: stateMeasurements(samples, stats),
		passed: true
	}
}

module.exports = {
	STATE_ORDER,
	changedFiles,
	measureIterationScenario,
	replaceExactlyOnce
}
