#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[rust-conformance-placeholder] ERROR: ${message}`)
	process.exit(2)
}

function parseBool(value, flagName) {
	if (value === 'true' || value === '1') {
		return true
	}
	if (value === 'false' || value === '0') {
		return false
	}
	fail(`${flagName} must be true|false|1|0 (received: ${value})`)
}

function parseArgs(argv) {
	const options = {
		targetId: 'rust',
		tier: 'tier1',
		allowlistPath: null,
		fixtureRoot: null,
		reportPath: null,
		strictNativeSurface: true,
		corpusManifestPath: null,
		sliceId: null,
	}

	for (let index = 2; index < argv.length; index += 1) {
		const arg = argv[index]
		if (arg === '--target-id') {
			options.targetId = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--tier') {
			options.tier = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--allowlist-path') {
			options.allowlistPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--fixture-root') {
			options.fixtureRoot = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--report-path') {
			options.reportPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--strict-native-surface') {
			options.strictNativeSurface = parseBool(argv[index + 1], '--strict-native-surface')
			index += 1
			continue
		}
		if (arg === '--corpus-manifest-path') {
			options.corpusManifestPath = argv[index + 1]
			index += 1
			continue
		}
		if (arg === '--slice-id') {
			options.sliceId = argv[index + 1]
			index += 1
			continue
		}
		fail(`unknown argument: ${arg}`)
	}

	if (options.targetId !== 'rust') {
		fail(`targetId must be rust for this adapter (received: ${options.targetId})`)
	}
	if (options.tier.length === 0) {
		fail('tier must not be empty')
	}
	if (options.allowlistPath == null || options.allowlistPath.length === 0) {
		fail('missing required --allowlist-path')
	}
	if (options.fixtureRoot == null || options.fixtureRoot.length === 0) {
		fail('missing required --fixture-root')
	}
	if (options.reportPath == null || options.reportPath.length === 0) {
		fail('missing required --report-path')
	}

	return options
}

function writeJson(filePath, payload) {
	const absolutePath = path.resolve(filePath)
	fs.mkdirSync(path.dirname(absolutePath), { recursive: true })
	fs.writeFileSync(absolutePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8')
}

function main() {
	const options = parseArgs(process.argv)
	const reason = 'placeholder_not_implemented_in_this_repo'

	console.log(`PORTABLE_CONFORMANCE_RUNNER_START target=${options.targetId} tier=${options.tier}`)
	console.log(`PORTABLE_CONFORMANCE_RUNNER_SKIP target=${options.targetId} tier=${options.tier} reason=${reason}`)

	const report = {
		schemaVersion: 1,
		contractId: 'reflaxe.family.std.portable_conformance_runner',
		contractVersion: '1.0.0',
		targetId: options.targetId,
		tier: options.tier,
		strictNativeSurface: options.strictNativeSurface,
		status: 'skip',
		summary: {
			total: 0,
			passed: 0,
			failed: 0,
			skipped: 0,
		},
		fixtures: [],
		adapter: {
			mode: 'placeholder',
			reason,
		},
		inputs: {
			allowlistPath: options.allowlistPath,
			fixtureRoot: options.fixtureRoot,
			reportPath: options.reportPath,
			corpusManifestPath: options.corpusManifestPath,
			sliceId: options.sliceId,
		},
	}

	writeJson(options.reportPath, report)
}

main()
