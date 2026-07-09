#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[stdlib-matrix] ERROR: ${message}`)
	process.exit(1)
}

function makeDeterministicMapFromEvidenceEntries(entries, statusName, evidenceByModule) {
	if (!Array.isArray(entries)) {
		fail(`evidence entries for ${statusName} must be an array`)
	}
	const modules = []
	for (const entry of entries) {
		if (entry == null || typeof entry !== 'object') {
			fail(`invalid evidence entry in ${statusName}: expected object`)
		}
		if (typeof entry.module !== 'string' || entry.module.trim() === '') {
			fail(`invalid evidence entry in ${statusName}: missing module`)
		}
		if (!Array.isArray(entry.evidence) || entry.evidence.length === 0) {
			fail(`invalid evidence entry in ${statusName}:${entry.module}: evidence must be a non-empty array`)
		}
		const evidenceItems = entry.evidence
			.map((value) => {
				if (typeof value !== 'string' || value.trim() === '') {
					fail(`invalid evidence value in ${statusName}:${entry.module}`)
				}
				return value
			})
			.sort((left, right) => (left < right ? -1 : left > right ? 1 : 0))
		modules.push(entry.module)
		evidenceByModule.set(entry.module, evidenceItems)
	}
	modules.sort((left, right) => (left < right ? -1 : left > right ? 1 : 0))
	return new Set(modules)
}

function listHxFilesRecursive(rootDir, out) {
	const entries = fs.readdirSync(rootDir, { withFileTypes: true })
	for (const entry of entries) {
		const absolutePath = path.join(rootDir, entry.name)
		if (entry.isDirectory()) {
			listHxFilesRecursive(absolutePath, out)
		} else if (entry.isFile() && entry.name.endsWith('.hx')) {
			out.push(absolutePath)
		}
	}
}

function moduleFromStdOverridePath(stdRoot, absolutePath) {
	const rel = path.relative(stdRoot, absolutePath).split(path.sep).join('/')
	return rel.slice(0, -3).split('/').join('.')
}

function main() {
	const repoRoot = path.resolve(__dirname, '..', '..')
	const baselinePath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_BASELINE_HAXE_4_3_7.json')
	const evidencePath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_EVIDENCE_HAXE_4_3_7.json')
	const stdOverrideRoot = path.join(repoRoot, 'packages', 'reflaxe.ocaml', 'std', 'ocaml', '_std')
	const outputPath = path.join(repoRoot, 'docs', '02-user-guide', 'STDLIB_PORTABLE_PARITY_MATRIX.md')

	if (!fs.existsSync(baselinePath)) {
		fail(`missing baseline file: ${baselinePath}`)
	}
	if (!fs.existsSync(evidencePath)) {
		fail(`missing evidence file: ${evidencePath}`)
	}
	if (!fs.existsSync(stdOverrideRoot)) {
		fail(`missing std override root: ${stdOverrideRoot}`)
	}

	const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'))
	const evidence = JSON.parse(fs.readFileSync(evidencePath, 'utf8'))
	if (!Array.isArray(baseline.modules)) {
		fail(`baseline file is missing modules array: ${baselinePath}`)
	}
	if (evidence == null || typeof evidence !== 'object') {
		fail(`evidence file is invalid JSON object: ${evidencePath}`)
	}
	if (evidence.haxeVersion !== baseline.haxeVersion) {
		fail(`evidence haxeVersion mismatch: baseline=${baseline.haxeVersion} evidence=${evidence.haxeVersion}`)
	}
	if (evidence.statusEvidence == null || typeof evidence.statusEvidence !== 'object') {
		fail(`evidence file is missing statusEvidence object: ${evidencePath}`)
	}

	const overrideFiles = []
	listHxFilesRecursive(stdOverrideRoot, overrideFiles)
	const overrideModules = new Set(overrideFiles.map((filePath) => moduleFromStdOverridePath(stdOverrideRoot, filePath)))

	const runtimeEvidenceByModule = new Map()
	const loweringEvidenceByModule = new Map()
	const passthroughEvidenceByModule = new Map()
	const overrideEvidenceByModule = new Map()
	const runtimeBackedModules = makeDeterministicMapFromEvidenceEntries(
		evidence.statusEvidence.runtime_backed,
		'runtime_backed',
		runtimeEvidenceByModule
	)
	const loweringIntrinsicModules = makeDeterministicMapFromEvidenceEntries(
		evidence.statusEvidence.lowering_intrinsic,
		'lowering_intrinsic',
		loweringEvidenceByModule
	)
	const passthroughVerifiedModules = makeDeterministicMapFromEvidenceEntries(
		evidence.statusEvidence.passthrough_verified,
		'passthrough_verified',
		passthroughEvidenceByModule
	)
	const overrideEvidenceModules = evidence.statusEvidence.override != null
		? makeDeterministicMapFromEvidenceEntries(
			evidence.statusEvidence.override,
			'override',
			overrideEvidenceByModule
		)
		: new Set()

	const statusRows = []
	const counts = {
		override: 0,
		runtime_backed: 0,
		lowering_intrinsic: 0,
		passthrough_verified: 0,
		passthrough_unverified: 0,
	}

	const modules = [...baseline.modules].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
	const baselineModuleSet = new Set(modules)
	for (const moduleName of runtimeBackedModules) {
		if (!baselineModuleSet.has(moduleName)) {
			fail(`runtime_backed module not in baseline: ${moduleName}`)
		}
	}
	for (const moduleName of loweringIntrinsicModules) {
		if (!baselineModuleSet.has(moduleName)) {
			fail(`lowering_intrinsic module not in baseline: ${moduleName}`)
		}
	}
	for (const moduleName of passthroughVerifiedModules) {
		if (!baselineModuleSet.has(moduleName)) {
			fail(`passthrough_verified module not in baseline: ${moduleName}`)
		}
	}
	for (const moduleName of overrideEvidenceModules) {
		if (!baselineModuleSet.has(moduleName)) {
			fail(`override module not in baseline: ${moduleName}`)
		}
	}

	for (const moduleName of modules) {
		let status = 'passthrough_unverified'
		let evidenceText = 'upstream std module, no explicit portable evidence yet'
		if (overrideModules.has(moduleName)) {
			status = 'override'
			const overrideEvidence = [`packages/reflaxe.ocaml/std/ocaml/_std/${moduleName.split('.').join('/')}.hx`]
			if (overrideEvidenceModules.has(moduleName)) {
				overrideEvidence.push(...overrideEvidenceByModule.get(moduleName))
			}
			evidenceText = overrideEvidence.join('; ')
		} else if (runtimeBackedModules.has(moduleName)) {
			status = 'runtime_backed'
			evidenceText = runtimeEvidenceByModule.get(moduleName).join('; ')
		} else if (loweringIntrinsicModules.has(moduleName)) {
			status = 'lowering_intrinsic'
			evidenceText = loweringEvidenceByModule.get(moduleName).join('; ')
		} else if (passthroughVerifiedModules.has(moduleName)) {
			status = 'passthrough_verified'
			evidenceText = passthroughEvidenceByModule.get(moduleName).join('; ')
		}
		counts[status] += 1
		statusRows.push(`| \`${moduleName}\` | \`${status}\` | ${evidenceText} |`)
	}

	const markdown = [
		'# Portable Stdlib Parity Matrix (OCaml, Haxe 4.3.7 baseline)',
		'',
		'Generated from:',
		`- \`docs/00-project/STDLIB_PORTABLE_BASELINE_HAXE_4_3_7.json\``,
		`- \`docs/00-project/STDLIB_PORTABLE_EVIDENCE_HAXE_4_3_7.json\``,
		`- tracked overrides under \`packages/reflaxe.ocaml/std/ocaml/_std/\``,
		'',
		`Summary: \`${modules.length}\` modules total, \`${counts.override}\` overrides, \`${counts.runtime_backed}\` runtime-backed, \`${counts.lowering_intrinsic}\` lowering-intrinsic, \`${counts.passthrough_verified}\` passthrough-verified, \`${counts.passthrough_unverified}\` passthrough-unverified.`,
		'',
		'| Module | Status | Evidence |',
		'|---|---|---|',
		...statusRows,
		'',
	]

	fs.writeFileSync(outputPath, `${markdown.join('\n')}\n`, 'utf8')
	console.log(`[stdlib-matrix] wrote ${outputPath} (${modules.length} modules)`)
}

main()
