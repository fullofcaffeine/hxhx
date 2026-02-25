#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function fail(message) {
	console.error(`[stdlib-matrix] ERROR: ${message}`)
	process.exit(1)
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
	const baselinePath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json')
	const stdOverrideRoot = path.join(repoRoot, 'packages', 'reflaxe.ocaml', 'std', '_std')
	const outputPath = path.join(repoRoot, 'docs', '02-user-guide', 'STDLIB_PORTABLE_PARITY_MATRIX.md')

	if (!fs.existsSync(baselinePath)) {
		fail(`missing baseline file: ${baselinePath}`)
	}
	if (!fs.existsSync(stdOverrideRoot)) {
		fail(`missing std override root: ${stdOverrideRoot}`)
	}

	const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'))
	if (!Array.isArray(baseline.modules)) {
		fail(`baseline file is missing modules array: ${baselinePath}`)
	}

	const overrideFiles = []
	listHxFilesRecursive(stdOverrideRoot, overrideFiles)
	const overrideModules = new Set(overrideFiles.map((filePath) => moduleFromStdOverridePath(stdOverrideRoot, filePath)))

	const runtimeBackedModules = new Set([
		'Array',
		'Date',
		'EReg',
		'Math',
		'String',
		'Sys',
		'haxe.io.Bytes',
		'haxe.io.BytesBuffer',
		'haxe.io.BytesData',
		'haxe.io.FPHelper',
		'haxe.io.Input',
		'haxe.io.Output',
		'sys.FileSystem',
		'sys.io.File',
		'sys.io.FileInput',
		'sys.io.FileOutput',
		'sys.io.Process',
		'sys.io.Stdio',
	])

	const statusRows = []
	let overrideCount = 0
	let runtimeCount = 0
	let passthroughCount = 0

	const modules = [...baseline.modules].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
	for (const moduleName of modules) {
		let status = 'passthrough_or_unverified'
		let evidence = 'upstream std module, no local override yet'
		if (overrideModules.has(moduleName)) {
			status = 'override'
			evidence = `packages/reflaxe.ocaml/std/_std/${moduleName.split('.').join('/')}.hx`
			overrideCount += 1
		} else if (runtimeBackedModules.has(moduleName)) {
			status = 'runtime_backed'
			evidence = 'runtime-backed or lowered in backend'
			runtimeCount += 1
		} else {
			passthroughCount += 1
		}
		statusRows.push(`| \`${moduleName}\` | \`${status}\` | ${evidence} |`)
	}

	const markdown = [
		'# Portable Stdlib Parity Matrix (OCaml, Haxe 4.3.7 baseline)',
		'',
		'Generated from:',
		`- \`docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json\``,
		`- tracked overrides under \`packages/reflaxe.ocaml/std/_std/\``,
		'',
		`Summary: \`${modules.length}\` modules total, \`${overrideCount}\` overrides, \`${runtimeCount}\` runtime-backed, \`${passthroughCount}\` passthrough/unverified.`,
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
