#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[stdlib-closure] ERROR: ${message}`)
	process.exit(1)
}

function parseMatrixStatusRows(matrixMarkdown) {
	const statusesByModule = new Map()
	const lines = matrixMarkdown.split(/\r?\n/u)
	const rowPattern = /^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|/u
	for (const line of lines) {
		const match = rowPattern.exec(line)
		if (match == null) {
			continue
		}
		statusesByModule.set(match[1], match[2])
	}
	return statusesByModule
}

function closureGroupForModule(moduleName) {
	const segments = moduleName.split('.')
	if (segments.length === 1) {
		return 'core'
	}
	if (segments[0] === 'haxe' && segments.length >= 2) {
		const haxeFamily = segments[1]
		const explicitFamilies = new Set([
			'atomic',
			'crypto',
			'display',
			'ds',
			'exceptions',
			'extern',
			'format',
			'http',
			'io',
			'iterators',
			'macro',
			'rtti',
			'xml',
			'zip',
		])
		if (explicitFamilies.has(haxeFamily)) {
			return `haxe.${haxeFamily}`
		}
		return 'haxe.core'
	}
	if (segments[0] === 'sys' && segments.length >= 2) {
		const sysFamily = segments[1]
		const explicitSysFamilies = new Set(['db', 'io', 'net', 'ssl', 'thread'])
		if (explicitSysFamilies.has(sysFamily)) {
			return `sys.${sysFamily}`
		}
		return 'sys.core'
	}
	return segments[0]
}

function chunkModules(modules, chunkSize) {
	const chunks = []
	for (let index = 0; index < modules.length; index += chunkSize) {
		chunks.push(modules.slice(index, index + chunkSize))
	}
	return chunks
}

function buildBuckets(missingModules, chunkSize) {
	const grouped = new Map()
	for (const moduleName of missingModules) {
		const group = closureGroupForModule(moduleName)
		if (!grouped.has(group)) {
			grouped.set(group, [])
		}
		grouped.get(group).push(moduleName)
	}

	const buckets = []
	const orderedGroups = [...grouped.keys()].sort((left, right) => (left < right ? -1 : left > right ? 1 : 0))
	for (const group of orderedGroups) {
		const groupModules = grouped.get(group)
		const chunks = chunkModules(groupModules, chunkSize)
		for (let index = 0; index < chunks.length; index += 1) {
			const bucketIndex = index + 1
			const paddedIndex = String(bucketIndex).padStart(2, '0')
			buckets.push({
				bucketKey: `${group}-${paddedIndex}`,
				group,
				modules: chunks[index],
			})
		}
	}

	return buckets
}

function main() {
	const repoRoot = path.resolve(__dirname, '..', '..')
	const baselinePath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_BASELINE_HAXE_4_3_7.json')
	const matrixPath = path.join(repoRoot, 'docs', '02-user-guide', 'STDLIB_PORTABLE_PARITY_MATRIX.md')
	const outputPath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_CLOSURE_WORKLIST_HAXE_4_3_7.json')

	if (!fs.existsSync(baselinePath)) {
		fail(`missing baseline file: ${baselinePath}`)
	}
	if (!fs.existsSync(matrixPath)) {
		fail(`missing parity matrix file: ${matrixPath}`)
	}

	const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'))
	if (!Array.isArray(baseline.modules)) {
		fail(`baseline file is missing modules array: ${baselinePath}`)
	}

	const matrixMarkdown = fs.readFileSync(matrixPath, 'utf8')
	const statusesByModule = parseMatrixStatusRows(matrixMarkdown)

	const missingModules = []
	for (const moduleName of baseline.modules) {
		if (!statusesByModule.has(moduleName)) {
			fail(`parity matrix is missing status row for module: ${moduleName}`)
		}
		const status = statusesByModule.get(moduleName)
		if (status === 'passthrough_or_unverified' || status === 'passthrough_unverified') {
			missingModules.push(moduleName)
		}
	}

	missingModules.sort((left, right) => (left < right ? -1 : left > right ? 1 : 0))
	const chunkSize = 12
	const buckets = buildBuckets(missingModules, chunkSize)

	const worklist = {
		schemaVersion: 1,
		name: 'ocaml_portable_closure_worklist',
		haxeVersion: baseline.haxeVersion,
		baselineRef: 'docs/00-project/STDLIB_PORTABLE_BASELINE_HAXE_4_3_7.json',
		matrixRef: 'docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md',
		parentIssueId: 'haxe.ocaml-yfh.5',
		statusFilter: ['passthrough_or_unverified', 'passthrough_unverified'],
		bucketChunkSize: chunkSize,
		totals: {
			baselineModules: baseline.modules.length,
			missingModules: missingModules.length,
			bucketCount: buckets.length,
		},
		missingModules,
		buckets,
	}

	fs.writeFileSync(outputPath, `${JSON.stringify(worklist, null, 2)}\n`, 'utf8')
	console.log(
		`[stdlib-closure] wrote ${outputPath} (${worklist.totals.missingModules} missing modules, ${worklist.totals.bucketCount} buckets)`
	)
}

main()
