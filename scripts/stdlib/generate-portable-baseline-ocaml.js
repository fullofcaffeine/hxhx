#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

function resolveRepoRoot() {
	return path.resolve(__dirname, '..', '..')
}

function resolveUpstreamDir(root) {
	const configured = process.env.HAXE_UPSTREAM_DIR
	if (configured && configured.trim().length > 0) {
		return path.resolve(configured)
	}
	return path.join(root, 'vendor', 'haxe')
}

function fail(message) {
	console.error(`[stdlib-baseline] ERROR: ${message}`)
	process.exit(1)
}

function walkFiles(dir, out) {
	const entries = fs.readdirSync(dir, { withFileTypes: true })
	for (const entry of entries) {
		const abs = path.join(dir, entry.name)
		if (entry.isDirectory()) {
			walkFiles(abs, out)
		} else if (entry.isFile() && entry.name.endsWith('.hx')) {
			out.push(abs)
		}
	}
}

function toModuleName(stdDir, absolutePath) {
	const rel = path.relative(stdDir, absolutePath).split(path.sep).join('/')
	return rel.slice(0, -3).split('/').join('.')
}

function buildPortableModuleList(stdDir, excludedNamespaces) {
	const files = []
	walkFiles(stdDir, files)
	const excluded = new Set(excludedNamespaces)
	const modules = []
	for (const absolutePath of files) {
		const moduleName = toModuleName(stdDir, absolutePath)
		const rootNamespace = moduleName.split('.')[0]
		if (excluded.has(rootNamespace)) {
			continue
		}
		modules.push(moduleName)
	}
	modules.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
	return Array.from(new Set(modules))
}

function main() {
	const root = resolveRepoRoot()
	const upstreamDir = resolveUpstreamDir(root)
	const stdDir = path.join(upstreamDir, 'std')
	if (!fs.existsSync(stdDir) || !fs.statSync(stdDir).isDirectory()) {
		fail(`missing upstream std directory: ${stdDir} (set HAXE_UPSTREAM_DIR or provide vendor/haxe/std)`)
	}

	const excludedNamespaces = [
		'_std',
		'cpp',
		'cs',
		'eval',
		'flash',
		'hl',
		'jvm',
		'java',
		'js',
		'lua',
		'neko',
		'php',
		'python',
	]

	const modules = buildPortableModuleList(stdDir, excludedNamespaces)
	const outputPath = path.join(root, 'docs', '00-project', 'STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json')
	const payload = {
		schemaVersion: 1,
		name: 'ocaml_portable_stdlib_baseline',
		haxeVersion: '4.3.7',
		baselinePolicy: 'platform_agnostic_plus_sys',
		upstreamStdPath: 'vendor/haxe/std',
		excludedTopLevelNamespaces: excludedNamespaces,
		modules,
	}

	fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8')
	console.log(`[stdlib-baseline] wrote ${outputPath} (${modules.length} modules)`)
}

main()
