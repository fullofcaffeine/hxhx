#!/usr/bin/env node

const fs = require('fs')
const cp = require('child_process')
const path = require('path')

function fail(message) {
	console.error(`[ci:stdlib] ERROR: ${message}`)
	process.exitCode = 1
}

function runNodeScript(scriptPath, env) {
	try {
		cp.execFileSync('node', [scriptPath], {
			stdio: 'inherit',
			env: { ...process.env, ...env },
		})
		return true
	} catch (_) {
		fail(`failed to execute baseline generator: ${scriptPath}`)
		return false
	}
}

function readJson(filePath) {
	try {
		return JSON.parse(fs.readFileSync(filePath, 'utf8'))
	} catch (error) {
		fail(`invalid JSON in ${filePath}: ${error}`)
		return null
	}
}

function summarize(items, limit) {
	const shown = items.slice(0, limit).map((item) => `- ${item}`)
	const suffix = items.length > limit ? `\n- ... (${items.length - limit} more)` : ''
	return `${shown.join('\n')}${suffix}`
}

function stableSorted(values) {
	return [...values].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

function main() {
	const repoRoot = path.resolve(__dirname, '..', '..')
	const baselinePath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_BASELINE_HAXE_4_3_7.json')
	const tempPath = path.join(repoRoot, '.tmp', 'stdlib-baseline-generated.json')
	const generatorPath = path.join(repoRoot, 'scripts', 'stdlib', 'generate-portable-baseline-ocaml.js')

	if (!fs.existsSync(baselinePath)) {
		fail(`missing baseline file: ${baselinePath}`)
		process.exit(process.exitCode || 1)
	}

	fs.mkdirSync(path.dirname(tempPath), { recursive: true })
	const originalContent = fs.readFileSync(baselinePath, 'utf8')
	let generatedWritten = false
	try {
		if (runNodeScript(generatorPath, {})) {
			const generatedContent = fs.readFileSync(baselinePath, 'utf8')
			fs.writeFileSync(tempPath, generatedContent, 'utf8')
			generatedWritten = true
		}
	} finally {
		fs.writeFileSync(baselinePath, originalContent, 'utf8')
	}
	if (!generatedWritten) {
		process.exit(process.exitCode || 1)
	}

	const tracked = readJson(baselinePath)
	const generated = readJson(tempPath)
	if (tracked == null || generated == null) {
		process.exit(process.exitCode || 1)
	}

	const trackedModules = stableSorted(Array.isArray(tracked.modules) ? tracked.modules : [])
	const generatedModules = stableSorted(Array.isArray(generated.modules) ? generated.modules : [])
	const trackedSet = new Set(trackedModules)
	const generatedSet = new Set(generatedModules)

	const missing = generatedModules.filter((moduleName) => !trackedSet.has(moduleName))
	const stale = trackedModules.filter((moduleName) => !generatedSet.has(moduleName))

	if (missing.length > 0) {
		fail(`tracked baseline is missing modules present in generated baseline:\n${summarize(missing, 25)}`)
	}
	if (stale.length > 0) {
		fail(`tracked baseline has stale modules not present in generated baseline:\n${summarize(stale, 25)}`)
	}

	if (process.exitCode) {
		process.exit(process.exitCode)
	}

	console.log(`[ci:stdlib] OK: portable baseline matches generated module set (${trackedModules.length} modules)`)
}

main()
