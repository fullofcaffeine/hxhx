#!/usr/bin/env node

const fs = require('fs')
const cp = require('child_process')

function fail(msg) {
	console.error(`[ci:guards] ERROR: ${msg}`)
	process.exitCode = 1
}

function gitTrackedAll() {
	try {
		const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
		return out.split('\0').filter(Boolean)
	} catch (_) {
		return []
	}
}

function gitStagedFiles() {
	try {
		const out = cp.execFileSync('git', ['diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z'], { encoding: 'utf8' })
		return out.split('\0').filter(Boolean)
	} catch (_) {
		return []
	}
}

function shouldScanText(path) {
	if (path.startsWith('.beads/')) return false
	if (path.startsWith('packages/hxhx/bootstrap_out/')) return false
	if (path.startsWith('packages/hxhx-macro-host/bootstrap_out/')) return false
	const lower = path.toLowerCase()
	if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.ico')) return false
	if (lower.endsWith('.pdf') || lower.endsWith('.zip') || lower.endsWith('.gz') || lower.endsWith('.tar') || lower.endsWith('.tgz')) return false
	if (lower.endsWith('.exe') || lower.endsWith('.bc') || lower.endsWith('.a') || lower.endsWith('.so') || lower.endsWith('.dylib')) return false
	return true
}

const patterns = [
	{
		name: 'macos_home_path',
		re: /\/Users\/[^/\s]+\/[^\s"'`)]+/g,
	},
	{
		name: 'linux_home_path',
		re: /\/home\/(?!runner\/)[^/\s]+\/[^\s"'`)]+/g,
	},
	{
		name: 'windows_home_path',
		re: /[A-Za-z]:\\\\Users\\\\[^\\\s]+\\\\[^\s"'`)]+/g,
	},
]

const violations = []
const maxViolations = 200

const stagedOnly = process.argv.includes('--staged')
const files = stagedOnly ? gitStagedFiles() : gitTrackedAll()

for (const path of files) {
	if (!shouldScanText(path)) continue

	let text
	try {
		text = fs.readFileSync(path, 'utf8')
	} catch (_) {
		continue
	}

	const lines = text.split('\n')
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i]
		for (const pattern of patterns) {
			pattern.re.lastIndex = 0
			let m
			while ((m = pattern.re.exec(line)) !== null) {
				violations.push({
					path,
					line: i + 1,
					pattern: pattern.name,
					match: m[0],
				})
				if (violations.length >= maxViolations) break
			}
			if (violations.length >= maxViolations) break
		}
		if (violations.length >= maxViolations) break
	}
	if (violations.length >= maxViolations) break
}

if (violations.length > 0) {
	const lines = violations.slice(0, 40).map((v) => `- ${v.path}:${v.line} [${v.pattern}] ${v.match}`)
	const extra = violations.length > 40 ? `\n- ... (${violations.length - 40} more)` : ''
	fail(`machine-local absolute paths found in tracked text:\n${lines.join('\n')}${extra}`)
} else {
	const scope = stagedOnly ? 'staged files' : 'tracked files'
	console.log(`[ci:guards] OK: no machine-local absolute paths found in ${scope}`)
}
