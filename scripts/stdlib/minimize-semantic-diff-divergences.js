#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

function fail(message) {
	console.error(`[semantic-diff] ERROR: ${message}`)
	process.exit(1)
}

function parseArgs(argv) {
	const options = {
		reportPath: null,
		fixtureRoot: 'test/portable/fixtures',
		outDir: 'test/portable/semantic_diff/generated',
		printJson: true,
	}

	for (let index = 2; index < argv.length; index += 1) {
		const arg = argv[index]
		if (arg === '--divergence-report') {
			options.reportPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--fixture-root') {
			options.fixtureRoot = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--out-dir') {
			options.outDir = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--no-print-json') {
			options.printJson = false
			continue
		}
		fail(`unknown argument: ${arg}`)
	}

	if (options.reportPath == null || options.reportPath.length === 0) {
		fail('--divergence-report is required')
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

function runReplayCommand(command, repoRoot) {
	const result = spawnSync('bash', ['-lc', command], {
		cwd: repoRoot,
		encoding: 'utf8',
		maxBuffer: 1024 * 1024 * 20,
	})
	const stdout = normalizeOutput(result.stdout)
	const stderr = normalizeOutput(result.stderr)
	const exitCode = result.status ?? 1
	if (result.error != null) {
		return {
			exitCode,
			stdout,
			stderr: normalizeOutput(`${stderr}\n${String(result.error.message)}`),
		}
	}
	return { exitCode, stdout, stderr }
}

function snapshotDiff(leftSnapshot, rightSnapshot) {
	const differingFields = []
	if (leftSnapshot.exitCode !== rightSnapshot.exitCode) {
		differingFields.push('exitCode')
	}
	if (leftSnapshot.stdout !== rightSnapshot.stdout) {
		differingFields.push('stdout')
	}
	if (leftSnapshot.stderr !== rightSnapshot.stderr) {
		differingFields.push('stderr')
	}
	return differingFields
}

function evaluateDivergence(repoRoot, replayCommands) {
	const leftSnapshot = runReplayCommand(replayCommands.left, repoRoot)
	const rightSnapshot = runReplayCommand(replayCommands.right, repoRoot)
	const differingFields = snapshotDiff(leftSnapshot, rightSnapshot)
	return {
		diverged: differingFields.length > 0,
		differingFields,
		leftSnapshot,
		rightSnapshot,
	}
}

function assertReplayCommands(entry) {
	if (entry == null || typeof entry !== 'object') {
		fail('invalid divergence entry')
	}
	const replayCommands = entry.replayCommands
	if (replayCommands == null || typeof replayCommands !== 'object') {
		fail(`divergence entry missing replayCommands: ${entry.fixtureId}`)
	}
	const left = replayCommands.left
	const right = replayCommands.right
	if (typeof left !== 'string' || left.length === 0 || typeof right !== 'string' || right.length === 0) {
		fail(`divergence entry replayCommands must include left/right commands: ${entry.fixtureId}`)
	}
	return { left, right }
}

function findPrimarySourceFile(fixtureDir) {
	const mainPath = path.join(fixtureDir, 'src', 'Main.hx')
	if (fs.existsSync(mainPath) && fs.statSync(mainPath).isFile()) {
		return mainPath
	}
	const sourceRoot = path.join(fixtureDir, 'src')
	if (!fs.existsSync(sourceRoot) || !fs.statSync(sourceRoot).isDirectory()) {
		fail(`missing fixture src directory: ${fixtureDir}`)
	}
	const candidates = []
	const stack = [sourceRoot]
	while (stack.length > 0) {
		const current = stack.pop()
		const children = fs.readdirSync(current).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
		for (const child of children) {
			const childPath = path.join(current, child)
			const stat = fs.statSync(childPath)
			if (stat.isDirectory()) {
				stack.push(childPath)
			} else if (stat.isFile() && child.endsWith('.hx')) {
				candidates.push(childPath)
			}
		}
	}
	if (candidates.length === 0) {
		fail(`no .hx source files found in fixture: ${fixtureDir}`)
	}
	candidates.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
	return candidates[0]
}

function isLikelyStructuralLine(line) {
	const trimmed = line.trim()
	if (trimmed.length === 0) {
		return false
	}
	return /^(package|import|using|class|interface|enum|typedef|abstract|#if|#elseif|#else|#end|\{|\})\b/u.test(trimmed)
}

function countLines(value) {
	if (value.length === 0) {
		return 0
	}
	return value.split('\n').length
}

function safeApplyCandidate({
	sourcePath,
	currentContent,
	candidateContent,
	repoRoot,
	replayCommands,
}) {
	if (candidateContent === currentContent) {
		return {
			accepted: false,
			nextContent: currentContent,
			evaluation: null,
		}
	}
	fs.writeFileSync(sourcePath, candidateContent, 'utf8')
	const evaluation = evaluateDivergence(repoRoot, replayCommands)
	if (evaluation.diverged) {
		return {
			accepted: true,
			nextContent: candidateContent,
			evaluation,
		}
	}
	fs.writeFileSync(sourcePath, currentContent, 'utf8')
	return {
		accepted: false,
		nextContent: currentContent,
		evaluation,
	}
}

function reduceProgramLevel({
	sourcePath,
	initialContent,
	repoRoot,
	replayCommands,
}) {
	let currentContent = initialContent
	let currentEvaluation = evaluateDivergence(repoRoot, replayCommands)
	if (!currentEvaluation.diverged) {
		return {
			content: initialContent,
			evaluation: currentEvaluation,
			removedLineCount: 0,
			attemptedLineCount: 0,
		}
	}

	let removedLineCount = 0
	let attemptedLineCount = 0
	let changed = true
	while (changed) {
		changed = false
		const lines = currentContent.split('\n')
		for (let index = lines.length - 1; index >= 0; index -= 1) {
			const line = lines[index]
			if (isLikelyStructuralLine(line)) {
				continue
			}
			attemptedLineCount += 1
			const candidateLines = lines.slice(0, index).concat(lines.slice(index + 1))
			const candidateContent = candidateLines.join('\n')
			const candidateResult = safeApplyCandidate({
				sourcePath,
				currentContent,
				candidateContent,
				repoRoot,
				replayCommands,
			})
			if (!candidateResult.accepted) {
				continue
			}
			currentContent = candidateResult.nextContent
			currentEvaluation = candidateResult.evaluation
			removedLineCount += 1
			changed = true
			break
		}
	}

	return {
		content: currentContent,
		evaluation: currentEvaluation,
		removedLineCount,
		attemptedLineCount,
	}
}

function applyFirstReplacement(content, pattern, replacementText) {
	const match = pattern.exec(content)
	if (match == null || match.index < 0) {
		return null
	}
	return content.slice(0, match.index) + replacementText + content.slice(match.index + match[0].length)
}

function reduceExpressionLevel({
	sourcePath,
	initialContent,
	repoRoot,
	replayCommands,
}) {
	const rules = [
		{ id: 'string_to_empty', pattern: /"([^"\\]|\\.)*"/u, replacement: '""' },
		{ id: 'float_to_zero', pattern: /\b\d+\.\d+\b/u, replacement: '0.0' },
		{ id: 'int_to_zero', pattern: /\b\d+\b/u, replacement: '0' },
		{ id: 'true_to_false', pattern: /\btrue\b/u, replacement: 'false' },
	]

	let currentContent = initialContent
	let currentEvaluation = evaluateDivergence(repoRoot, replayCommands)
	if (!currentEvaluation.diverged) {
		return {
			content: initialContent,
			evaluation: currentEvaluation,
			acceptedRuleApplications: [],
			attemptedRuleApplications: 0,
		}
	}

	const acceptedRuleApplications = []
	let attemptedRuleApplications = 0
	for (const rule of rules) {
		let changed = true
		while (changed) {
			changed = false
			const candidateContent = applyFirstReplacement(currentContent, rule.pattern, rule.replacement)
			if (candidateContent == null || candidateContent === currentContent) {
				break
			}
			attemptedRuleApplications += 1
			const candidateResult = safeApplyCandidate({
				sourcePath,
				currentContent,
				candidateContent,
				repoRoot,
				replayCommands,
			})
			if (!candidateResult.accepted) {
				break
			}
			currentContent = candidateResult.nextContent
			currentEvaluation = candidateResult.evaluation
			acceptedRuleApplications.push(rule.id)
			changed = true
		}
	}

	return {
		content: currentContent,
		evaluation: currentEvaluation,
		acceptedRuleApplications,
		attemptedRuleApplications,
	}
}

function sanitizeFixtureId(fixtureId) {
	return fixtureId.replace(/[^a-zA-Z0-9._-]/g, '_')
}

function writeJson(filePath, payload) {
	fs.mkdirSync(path.dirname(filePath), { recursive: true })
	fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8')
}

function exportMinimizedFixture({
	outDir,
	index,
	fixtureId,
	sourceRelativePath,
	minimizedContent,
	metadata,
}) {
	const folderName = `${String(index).padStart(3, '0')}__${sanitizeFixtureId(fixtureId)}`
	const fixtureOutDir = path.join(outDir, folderName)
	const sourceOutPath = path.join(fixtureOutDir, sourceRelativePath)
	const metadataPath = path.join(fixtureOutDir, 'metadata.json')
	fs.mkdirSync(path.dirname(sourceOutPath), { recursive: true })
	fs.writeFileSync(sourceOutPath, minimizedContent, 'utf8')
	writeJson(metadataPath, metadata)
	return {
		folderName,
		sourceOutPath: sourceOutPath.split(path.sep).join('/'),
		metadataPath: metadataPath.split(path.sep).join('/'),
	}
}

function ensureDivergenceReportContract(report) {
	if (report == null || typeof report !== 'object') {
		fail('invalid divergence report payload')
	}
	if (!Array.isArray(report.divergences)) {
		fail('divergence report must contain divergences array')
	}
}

function main() {
	const options = parseArgs(process.argv)
	const repoRoot = path.resolve(__dirname, '..', '..')
	const reportPath = path.resolve(repoRoot, options.reportPath)
	const fixtureRoot = path.resolve(repoRoot, options.fixtureRoot)
	const outDir = path.resolve(repoRoot, options.outDir)
	const report = readJson(reportPath)
	ensureDivergenceReportContract(report)

	const sortedDivergences = [...report.divergences].sort((left, right) => {
		const leftId = typeof left.fixtureId === 'string' ? left.fixtureId : ''
		const rightId = typeof right.fixtureId === 'string' ? right.fixtureId : ''
		if (leftId < rightId) {
			return -1
		}
		if (leftId > rightId) {
			return 1
		}
		return 0
	})

	const results = []
	for (let index = 0; index < sortedDivergences.length; index += 1) {
		const divergence = sortedDivergences[index]
		const fixtureId = divergence.fixtureId
		if (typeof fixtureId !== 'string' || fixtureId.length === 0) {
			fail(`divergence entry missing fixtureId at index ${index}`)
		}

		const replayCommands = assertReplayCommands(divergence)
		const fixtureDir = path.join(fixtureRoot, fixtureId)
		if (!fs.existsSync(fixtureDir) || !fs.statSync(fixtureDir).isDirectory()) {
			fail(`fixture not found for divergence minimization: ${fixtureId}`)
		}

		const sourcePath = findPrimarySourceFile(fixtureDir)
		const sourceRelativePath = path.relative(fixtureDir, sourcePath).split(path.sep).join('/')
		const originalContent = fs.readFileSync(sourcePath, 'utf8')
		let baselineEvaluation = null
		let finalEvaluation = null
		let programResult = null
		let expressionResult = null
		let minimizedContent = originalContent

		try {
			baselineEvaluation = evaluateDivergence(repoRoot, replayCommands)
			if (!baselineEvaluation.diverged) {
				finalEvaluation = baselineEvaluation
				const metadata = {
					schemaVersion: 1,
					contractId: 'reflaxe.family.std.minimized_repro_fixture',
					contractVersion: '1.0.0',
					fixtureId,
					sourcePath: path.relative(repoRoot, sourcePath).split(path.sep).join('/'),
					replayCommands,
					status: 'not_reproducible',
					stats: {
						beforeBytes: Buffer.byteLength(originalContent, 'utf8'),
						afterBytes: Buffer.byteLength(originalContent, 'utf8'),
						beforeLines: countLines(originalContent),
						afterLines: countLines(originalContent),
						reducedBytes: 0,
						reducedLines: 0,
					},
					evidence: {
						baseline: baselineEvaluation,
						final: finalEvaluation,
					},
				}
				const exportResult = exportMinimizedFixture({
					outDir,
					index,
					fixtureId,
					sourceRelativePath,
					minimizedContent,
					metadata,
				})
				results.push({
					fixtureId,
					status: metadata.status,
					sourcePath: metadata.sourcePath,
					output: exportResult,
					stats: metadata.stats,
				})
				continue
			}

			programResult = reduceProgramLevel({
				sourcePath,
				initialContent: originalContent,
				repoRoot,
				replayCommands,
			})
			expressionResult = reduceExpressionLevel({
				sourcePath,
				initialContent: programResult.content,
				repoRoot,
				replayCommands,
			})
			minimizedContent = expressionResult.content
			finalEvaluation = expressionResult.evaluation

			if (!finalEvaluation.diverged) {
				fail(`minimizer lost divergence for fixture ${fixtureId}`)
			}

			const beforeBytes = Buffer.byteLength(originalContent, 'utf8')
			const afterBytes = Buffer.byteLength(minimizedContent, 'utf8')
			const beforeLines = countLines(originalContent)
			const afterLines = countLines(minimizedContent)
			const metadata = {
				schemaVersion: 1,
				contractId: 'reflaxe.family.std.minimized_repro_fixture',
				contractVersion: '1.0.0',
				fixtureId,
				sourcePath: path.relative(repoRoot, sourcePath).split(path.sep).join('/'),
				replayCommands,
				status: 'minimized',
				stats: {
					beforeBytes,
					afterBytes,
					beforeLines,
					afterLines,
					reducedBytes: beforeBytes - afterBytes,
					reducedLines: beforeLines - afterLines,
				},
				phaseMetrics: {
					programLevel: {
						removedLineCount: programResult.removedLineCount,
						attemptedLineCount: programResult.attemptedLineCount,
					},
					expressionLevel: {
						attemptedRuleApplications: expressionResult.attemptedRuleApplications,
						acceptedRuleApplications: expressionResult.acceptedRuleApplications,
					},
				},
				evidence: {
					baseline: baselineEvaluation,
					final: finalEvaluation,
				},
			}

			const exportResult = exportMinimizedFixture({
				outDir,
				index,
				fixtureId,
				sourceRelativePath,
				minimizedContent,
				metadata,
			})

			results.push({
				fixtureId,
				status: metadata.status,
				sourcePath: metadata.sourcePath,
				output: exportResult,
				stats: metadata.stats,
				phaseMetrics: metadata.phaseMetrics,
			})
		} finally {
			fs.writeFileSync(sourcePath, originalContent, 'utf8')
		}
	}

	const manifest = {
		schemaVersion: 1,
		contractId: 'reflaxe.family.std.minimized_repro_manifest',
		contractVersion: '1.0.0',
		divergenceReportRef: path.relative(repoRoot, reportPath).split(path.sep).join('/'),
		fixtureRoot: path.relative(repoRoot, fixtureRoot).split(path.sep).join('/'),
		outDir: path.relative(repoRoot, outDir).split(path.sep).join('/'),
		summary: {
			divergenceCount: sortedDivergences.length,
			exportedCount: results.length,
			minimizedCount: results.filter((entry) => entry.status === 'minimized').length,
			notReproducibleCount: results.filter((entry) => entry.status === 'not_reproducible').length,
		},
		results,
	}

	const manifestPath = path.join(outDir, 'minimized_manifest.json')
	writeJson(manifestPath, manifest)
	console.log(
		`[semantic-diff] WROTE_MINIMIZED_MANIFEST path=${path.relative(repoRoot, manifestPath)} exported=${manifest.summary.exportedCount}`
	)
	if (options.printJson) {
		process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`)
	}
}

main()
