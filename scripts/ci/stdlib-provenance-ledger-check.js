#!/usr/bin/env node

const fs = require('fs')
const cp = require('child_process')

function fail(message) {
	console.error(`[ci:guards] ERROR: ${message}`)
	process.exitCode = 1
}

function gitTrackedUnder(path) {
	try {
		const out = cp.execFileSync('git', ['ls-files', '-z', '--', path], { encoding: 'utf8' })
		return out.split('\0').filter(Boolean)
	} catch (_) {
		return []
	}
}

function summarize(paths, limit) {
	const shown = paths.slice(0, limit).map((path) => `- ${path}`)
	const suffix = paths.length > limit ? `\n- ... (${paths.length - limit} more)` : ''
	return `${shown.join('\n')}${suffix}`
}

function main() {
	const noticesPath = 'THIRD_PARTY_NOTICES.md'
	const ledgerPath = 'docs/00-project/STDLIB_PROVENANCE_LEDGER.json'
	const stdlibRoot = 'packages/reflaxe.ocaml/std/_std/'

	if (!fs.existsSync(noticesPath)) {
		fail(`missing required third-party notice file: ${noticesPath}`)
		return
	}

	const noticesText = fs.readFileSync(noticesPath, 'utf8')
	if (!noticesText.includes('Haxe Standard Library')) {
		fail(`${noticesPath} must include a "Haxe Standard Library" notice section`)
	}
	if (!noticesText.includes('MIT')) {
		fail(`${noticesPath} must mention MIT licensing for the stdlib notice`)
	}

	if (!fs.existsSync(ledgerPath)) {
		fail(`missing stdlib provenance ledger: ${ledgerPath}`)
		return
	}

	let ledger = null
	try {
		ledger = JSON.parse(fs.readFileSync(ledgerPath, 'utf8'))
	} catch (error) {
		fail(`invalid JSON in ${ledgerPath}: ${error}`)
		return
	}

	if (ledger == null || typeof ledger !== 'object') {
		fail(`${ledgerPath} must contain a JSON object`)
		return
	}

	if (!Array.isArray(ledger.entries)) {
		fail(`${ledgerPath} must contain an entries array`)
		return
	}

	const trackedStdlibFiles = gitTrackedUnder(stdlibRoot)
		.filter((path) => path.endsWith('.hx'))
		.sort()

	if (trackedStdlibFiles.length === 0) {
		fail(`no tracked stdlib override files found under ${stdlibRoot}`)
		return
	}

	const seenPaths = new Set()
	const ledgerPaths = []
	for (const entry of ledger.entries) {
		if (entry == null || typeof entry !== 'object') {
			fail(`${ledgerPath} contains a non-object entry`)
			continue
		}

		const path = entry.path
		const provenanceKind = entry.provenanceKind
		const upstreamOraclePath = entry.upstreamOraclePath

		if (typeof path !== 'string' || path.length === 0) {
			fail(`${ledgerPath} entry is missing path`)
			continue
		}
		if (!path.startsWith(stdlibRoot)) {
			fail(`${ledgerPath} entry path must stay under ${stdlibRoot}: ${path}`)
		}
		if (!path.endsWith('.hx')) {
			fail(`${ledgerPath} entry path must be a .hx file: ${path}`)
		}
		if (seenPaths.has(path)) {
			fail(`${ledgerPath} contains duplicate path entry: ${path}`)
		}
		seenPaths.add(path)
		ledgerPaths.push(path)

		if (typeof provenanceKind !== 'string' || provenanceKind.length === 0) {
			fail(`${ledgerPath} entry is missing provenanceKind for ${path}`)
		}

		if (typeof upstreamOraclePath !== 'string' || upstreamOraclePath.length === 0) {
			fail(`${ledgerPath} entry is missing upstreamOraclePath for ${path}`)
		} else if (!upstreamOraclePath.startsWith('vendor/haxe/std/')) {
			fail(
				`${ledgerPath} entry upstreamOraclePath must point to vendor/haxe/std/** for ${path}: ${upstreamOraclePath}`
			)
		}
	}

	const trackedSet = new Set(trackedStdlibFiles)
	const ledgerSet = new Set(ledgerPaths)

	const missingCoverage = trackedStdlibFiles.filter((path) => !ledgerSet.has(path))
	const staleCoverage = ledgerPaths.filter((path) => !trackedSet.has(path))

	if (missingCoverage.length > 0) {
		fail(
			`stdlib provenance ledger missing tracked _std files:\n${summarize(missingCoverage, 20)}`
		)
	}
	if (staleCoverage.length > 0) {
		fail(
			`stdlib provenance ledger references non-tracked _std files:\n${summarize(staleCoverage, 20)}`
		)
	}

	if (process.exitCode) {
		process.exit(process.exitCode)
	}
	console.log(
		`[ci:guards] OK: stdlib provenance ledger covers ${trackedStdlibFiles.length} tracked _std files`
	)
}

main()
