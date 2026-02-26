#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[semantic-diff] ERROR: ${message}`)
	process.exit(1)
}

function parseArgs(argv) {
	const options = {
		leftReportPath: null,
		rightReportPath: null,
		outPath: null,
		printJson: true,
	}
	for (let index = 2; index < argv.length; index += 1) {
		const arg = argv[index]
		if (arg === '--left') {
			options.leftReportPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--right') {
			options.rightReportPath = argv[index + 1]
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

	if (options.leftReportPath == null || options.rightReportPath == null) {
		fail('--left and --right are required')
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

function ensureFixtureArray(report, reportLabel) {
	if (!Array.isArray(report.fixtures)) {
		fail(`${reportLabel} report must contain fixtures array`)
	}
}

function fixtureMap(report) {
	const map = new Map()
	for (const fixture of report.fixtures) {
		if (fixture == null || typeof fixture !== 'object') {
			fail(`invalid fixture entry in adapter report ${report.adapterId}`)
		}
		const fixtureId = fixture.fixtureId
		if (typeof fixtureId !== 'string' || fixtureId.length === 0) {
			fail(`fixture entry missing fixtureId in adapter report ${report.adapterId}`)
		}
		if (map.has(fixtureId)) {
			fail(`duplicate fixtureId in adapter report ${report.adapterId}: ${fixtureId}`)
		}
		map.set(fixtureId, fixture)
	}
	return map
}

function replayForFixture(report, fixture) {
	if (fixture != null && typeof fixture.replayCommand === 'string' && fixture.replayCommand.length > 0) {
		return fixture.replayCommand
	}
	if (typeof report.replayTemplate === 'string' && report.replayTemplate.length > 0 && fixture != null) {
		return report.replayTemplate.replace('<fixtureId>', fixture.fixtureId)
	}
	return ''
}

function snapshot(report, fixture) {
	if (fixture == null) {
		return {
			present: false,
			adapterId: report.adapterId,
			status: 'missing_fixture',
			compileExitCode: null,
			runExitCode: null,
			stdout: '',
			stderr: '',
			replayCommand: '',
		}
	}
	return {
		present: true,
		adapterId: report.adapterId,
		status: typeof fixture.status === 'string' ? fixture.status : 'unknown',
		compileExitCode: fixture.compileExitCode ?? null,
		runExitCode: fixture.runExitCode ?? null,
		stdout: normalizeOutput(fixture.stdout),
		stderr: normalizeOutput(fixture.stderr),
		replayCommand: replayForFixture(report, fixture),
	}
}

function compareSnapshots(leftSnapshot, rightSnapshot) {
	const differingFields = []
	if (leftSnapshot.present !== rightSnapshot.present) {
		differingFields.push('present')
	}
	if (leftSnapshot.status !== rightSnapshot.status) {
		differingFields.push('status')
	}
	if (leftSnapshot.compileExitCode !== rightSnapshot.compileExitCode) {
		differingFields.push('compileExitCode')
	}
	if (leftSnapshot.runExitCode !== rightSnapshot.runExitCode) {
		differingFields.push('runExitCode')
	}
	if (leftSnapshot.stdout !== rightSnapshot.stdout) {
		differingFields.push('stdout')
	}
	if (leftSnapshot.stderr !== rightSnapshot.stderr) {
		differingFields.push('stderr')
	}
	return differingFields
}

function writeJson(filePath, payload) {
	const absolutePath = path.resolve(filePath)
	fs.mkdirSync(path.dirname(absolutePath), { recursive: true })
	fs.writeFileSync(absolutePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8')
}

function main() {
	const options = parseArgs(process.argv)
	const repoRoot = path.resolve(__dirname, '..', '..')
	const leftReportPath = path.resolve(repoRoot, options.leftReportPath)
	const rightReportPath = path.resolve(repoRoot, options.rightReportPath)
	const leftReport = readJson(leftReportPath)
	const rightReport = readJson(rightReportPath)

	if (leftReport.schemaVersion !== 1 || rightReport.schemaVersion !== 1) {
		fail('adapter reports must have schemaVersion=1')
	}
	if (leftReport.contractId !== 'reflaxe.family.std.adapter_observable_report') {
		fail(`unexpected left contractId: ${leftReport.contractId}`)
	}
	if (rightReport.contractId !== 'reflaxe.family.std.adapter_observable_report') {
		fail(`unexpected right contractId: ${rightReport.contractId}`)
	}

	ensureFixtureArray(leftReport, 'left')
	ensureFixtureArray(rightReport, 'right')

	const leftMap = fixtureMap(leftReport)
	const rightMap = fixtureMap(rightReport)
	const fixtureIds = [...new Set([...leftMap.keys(), ...rightMap.keys()])].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
	const divergences = []

	for (const fixtureId of fixtureIds) {
		const leftFixture = leftMap.get(fixtureId) ?? null
		const rightFixture = rightMap.get(fixtureId) ?? null
		const leftSnapshot = snapshot(leftReport, leftFixture)
		const rightSnapshot = snapshot(rightReport, rightFixture)
		const differingFields = compareSnapshots(leftSnapshot, rightSnapshot)
		if (differingFields.length === 0) {
			continue
		}
		divergences.push({
			fixtureId,
			differingFields,
			left: leftSnapshot,
			right: rightSnapshot,
			replayCommands: {
				left: leftSnapshot.replayCommand,
				right: rightSnapshot.replayCommand,
			},
		})
	}

	const result = {
		schemaVersion: 1,
		contractId: 'reflaxe.family.std.semantic_diff_divergence_report',
		contractVersion: '1.0.0',
		leftAdapterId: leftReport.adapterId,
		rightAdapterId: rightReport.adapterId,
		leftReportRef: path.relative(repoRoot, leftReportPath).split(path.sep).join('/'),
		rightReportRef: path.relative(repoRoot, rightReportPath).split(path.sep).join('/'),
		summary: {
			fixturesCompared: fixtureIds.length,
			divergenceCount: divergences.length,
		},
		divergences,
	}

	if (options.outPath != null) {
		writeJson(path.resolve(repoRoot, options.outPath), result)
		console.log(
			`[semantic-diff] WROTE_DIVERGENCE_REPORT path=${options.outPath} compared=${result.summary.fixturesCompared} divergences=${result.summary.divergenceCount}`
		)
	}
	if (options.printJson) {
		process.stdout.write(`${JSON.stringify(result, null, 2)}\n`)
	}
}

main()
