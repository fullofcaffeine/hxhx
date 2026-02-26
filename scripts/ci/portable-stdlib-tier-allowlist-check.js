#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[ci:stdlib] ERROR: ${message}`)
	process.exitCode = 1
}

function readJson(filePath) {
	try {
		return JSON.parse(fs.readFileSync(filePath, 'utf8'))
	} catch (error) {
		fail(`invalid JSON in ${filePath}: ${error}`)
		return null
	}
}

function stableSorted(values) {
	return [...values].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

function parseArgs(argv) {
	let requestedTier = null
	for (let index = 2; index < argv.length; index += 1) {
		const arg = argv[index]
		if (arg === '--tier') {
			const value = argv[index + 1]
			if (value == null || value.length === 0) {
				fail('missing value for --tier (expected tier1 or tier2)')
				return { requestedTier: null }
			}
			requestedTier = value
			index += 1
			continue
		}
		fail(`unknown argument: ${arg}`)
		return { requestedTier: null }
	}
	return { requestedTier }
}

function assertSortedUnique(label, values) {
	const sorted = stableSorted(values)
	for (let i = 0; i < sorted.length; i += 1) {
		if (sorted[i] !== values[i]) {
			fail(`${label} must be lexicographically sorted`)
			return
		}
		if (i > 0 && sorted[i] === sorted[i - 1]) {
			fail(`${label} must not contain duplicates: ${sorted[i]}`)
			return
		}
	}
}

function ensureStringArray(label, value) {
	if (!Array.isArray(value)) {
		fail(`${label} must be an array`)
		return []
	}
	const out = []
	for (const entry of value) {
		if (typeof entry !== 'string' || entry.length === 0) {
			fail(`${label} contains a non-string or empty module entry`)
			continue
		}
		out.push(entry)
	}
	return out
}

function validateTierModules(tierName, modules, baselineSet) {
	assertSortedUnique(`tiers.${tierName}`, modules)
	for (const moduleName of modules) {
		if (!baselineSet.has(moduleName)) {
			fail(`tiers.${tierName} contains module not present in baseline: ${moduleName}`)
		}
	}
}

function main() {
	const { requestedTier } = parseArgs(process.argv)
	if (process.exitCode) {
		process.exit(process.exitCode)
	}

	const repoRoot = path.resolve(__dirname, '..', '..')
	const baselinePath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json')
	const allowlistPath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_ALLOWLIST_OCAML_4_3_7.json')
	const schemaPath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_ALLOWLIST_SCHEMA_V1.json')
	const schemaRef = 'docs/00-project/STDLIB_PORTABLE_ALLOWLIST_SCHEMA_V1.json'

	const baseline = readJson(baselinePath)
	const allowlist = readJson(allowlistPath)
	const schema = readJson(schemaPath)
	if (baseline == null || allowlist == null || schema == null) {
		process.exit(process.exitCode || 1)
	}

	if (allowlist.schemaVersion !== 1) {
		fail(`unexpected allowlist schemaVersion: ${allowlist.schemaVersion}`)
	}
	if (schema.schemaVersion !== 1) {
		fail(`unexpected allowlist schema schemaVersion: ${schema.schemaVersion}`)
	}
	if (allowlist.familyContract !== 'reflaxe.family.std.portable_allowlist') {
		fail(`allowlist familyContract must be reflaxe.family.std.portable_allowlist (received: ${allowlist.familyContract})`)
	}
	if (allowlist.contractVersion !== '1.0.0') {
		fail(`allowlist contractVersion must be 1.0.0 (received: ${allowlist.contractVersion})`)
	}
	if (allowlist.target !== 'ocaml') {
		fail(`allowlist target must be ocaml (received: ${allowlist.target})`)
	}
	if (allowlist.haxeVersion !== baseline.haxeVersion) {
		fail(`allowlist haxeVersion (${allowlist.haxeVersion}) must match baseline (${baseline.haxeVersion})`)
	}
	if (allowlist.baselineRef !== 'docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json') {
		fail(`allowlist baselineRef must point to docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`)
	}
	if (allowlist.schemaRef !== schemaRef) {
		fail(`allowlist schemaRef must point to ${schemaRef}`)
	}
	if (allowlist.tiers == null || typeof allowlist.tiers !== 'object') {
		fail('allowlist must include a tiers object')
		process.exit(process.exitCode || 1)
	}

	const baselineModules = ensureStringArray('baseline.modules', baseline.modules)
	const baselineSet = new Set(baselineModules)

	const tier1 = ensureStringArray('tiers.tier1', allowlist.tiers.tier1)
	const tier2 = ensureStringArray('tiers.tier2', allowlist.tiers.tier2)
	validateTierModules('tier1', tier1, baselineSet)
	validateTierModules('tier2', tier2, baselineSet)

	for (const moduleName of tier1) {
		if (!tier2.includes(moduleName)) {
			fail(`tiers.tier1 must be a subset of tiers.tier2 (missing in tier2: ${moduleName})`)
		}
	}

	if (requestedTier != null) {
		if (requestedTier !== 'tier1' && requestedTier !== 'tier2') {
			fail(`unsupported tier: ${requestedTier} (expected tier1 or tier2)`)
		} else {
			const target = requestedTier === 'tier1' ? tier1 : tier2
			console.log(`[ci:stdlib] OK: ${requestedTier} allowlist is valid (${target.length} modules)`)
		}
	}

	if (process.exitCode) {
		process.exit(process.exitCode)
	}
	if (requestedTier == null) {
		console.log(`[ci:stdlib] OK: tier allowlist is valid (tier1=${tier1.length}, tier2=${tier2.length})`)
	}
}

main()
