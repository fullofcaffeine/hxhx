#!/usr/bin/env node

const cp = require('child_process')
const fs = require('fs')

function fail(message) {
	console.error(`[ci:guards] ERROR: ${message}`)
	process.exitCode = 1
}

function trackedFiles() {
	try {
		const output = cp.execFileSync('git', ['ls-files', '-z'], {encoding: 'utf8'})
		return output.split('\0').filter((entry) => entry.length > 0)
	} catch (_) {
		return []
	}
}

function shouldScan(path) {
	if (path.startsWith('.beads/'))
		return false
	if (path === 'scripts/ci/reflaxe-ocaml-telemetry-define-check.js')
		return false
	if (path.startsWith('packages/hxhx/bootstrap_out/'))
		return false
	if (path.startsWith('packages/hxhx-macro-host/bootstrap_out/'))
		return false
	if (path.startsWith('vendor/'))
		return false
	const lower = path.toLowerCase()
	if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.ico'))
		return false
	if (lower.endsWith('.pdf') || lower.endsWith('.zip') || lower.endsWith('.gz') || lower.endsWith('.tar') || lower.endsWith('.tgz'))
		return false
	if (lower.endsWith('.exe') || lower.endsWith('.bc') || lower.endsWith('.a') || lower.endsWith('.so') || lower.endsWith('.dylib'))
		return false
	return true
}

function main() {
	const forbidden = [
		/\breflaxe_ocaml_profile\b/,
		/\breflaxe_ocaml_profile_detail\b/,
		/\breflaxe_ocaml_profile_class\b/,
		/\breflaxe_ocaml_profile_field\b/,
		/\bHXHX_STAGE0_PROFILE\b/,
		/\bHXHX_STAGE0_PROFILE_DETAIL\b/,
		/\bHXHX_STAGE0_PROFILE_CLASS\b/,
		/\bHXHX_STAGE0_PROFILE_FIELD\b/,
	]

	const offenders = []
	for (const path of trackedFiles()) {
		if (!shouldScan(path))
			continue
		let text = ''
		try {
			text = fs.readFileSync(path, 'utf8')
		} catch (_) {
			continue
		}
		for (const re of forbidden) {
			if (re.test(text)) {
				offenders.push({path, re: String(re)})
				break
			}
		}
	}

	if (offenders.length > 0) {
		const preview = offenders.slice(0, 30).map((item) => `- ${item.path} (matched ${item.re})`).join('\n')
		fail(`legacy Stage0 profiling define names detected:\n${preview}${offenders.length > 30 ? `\n- ... (${offenders.length - 30} more)` : ''}`)
		return
	}

	console.log('[ci:guards] OK: Stage0 telemetry define names are clean (no legacy profile-name collision)')
}

main()
