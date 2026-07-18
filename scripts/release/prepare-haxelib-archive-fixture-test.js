#!/usr/bin/env node
/** Exercises tracked-only staging and source-only archive finalization. */
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const helper = path.join(repoRoot, 'scripts/release/prepare-haxelib-archive.js')

function fail(message) {
	console.error(`[prepare-haxelib-archive-fixture] ERROR: ${message}`)
	process.exit(1)
}

function run(command, args, options = {}) {
	return cp.spawnSync(command, args, {
		cwd: options.cwd || repoRoot,
		encoding: 'utf8',
		shell: false
	})
}

function requireSuccess(label, result) {
	if (result.status !== 0) {
		fail(`${label} failed: ${result.stderr || result.stdout}`)
	}
}

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-haxelib-archive-fixture-'))
try {
	const sourceRepo = path.join(tempRoot, 'source')
	const packageRoot = path.join(sourceRepo, 'package')
	const stagedRoot = path.join(tempRoot, 'staged')
	const manifest = path.join(tempRoot, 'files.txt')
	fs.mkdirSync(path.join(packageRoot, 'src'), { recursive: true })
	fs.writeFileSync(path.join(sourceRepo, '.gitignore'), '*.cmo\n')
	fs.writeFileSync(path.join(packageRoot, 'src/Main.hx'), 'class Main {}\n')
	fs.writeFileSync(path.join(packageRoot, 'src/local-compiler-output.cmo'), 'must not ship\n')
	requireSuccess('git init', run('git', ['init', '-q'], { cwd: sourceRepo }))
	requireSuccess('git add', run('git', ['add', '.gitignore', 'package/src/Main.hx'], { cwd: sourceRepo }))

	requireSuccess('tracked staging', run(process.execPath, [helper, 'stage', '--repo', sourceRepo, '--package', 'package', '--out', stagedRoot]))
	if (!fs.existsSync(path.join(stagedRoot, 'src/Main.hx'))) {
		fail('tracked source file was not staged')
	}
	if (fs.existsSync(path.join(stagedRoot, 'src/local-compiler-output.cmo'))) {
		fail('ignored OCaml compiler output leaked into staging')
	}

	const injectedBinary = path.join(stagedRoot, 'src/injected.cmi')
	fs.writeFileSync(injectedBinary, 'must be rejected\n')
	const rejected = run(process.execPath, [helper, 'finalize', '--root', stagedRoot, '--manifest', manifest])
	if (rejected.status === 0 || !`${rejected.stdout}\n${rejected.stderr}`.includes('host/compiler-specific artifact')) {
		fail('finalization did not reject a compiler-specific artifact')
	}
	fs.rmSync(injectedBinary)

	fs.chmodSync(path.join(stagedRoot, 'src/Main.hx'), 0o755)
	requireSuccess('source finalization', run(process.execPath, [helper, 'finalize', '--root', stagedRoot, '--manifest', manifest]))
	if (fs.readFileSync(manifest, 'utf8') !== 'src/Main.hx\n') {
		fail('archive manifest was not stable and package-relative')
	}
	if ((fs.statSync(path.join(stagedRoot, 'src/Main.hx')).mode & 0o777) !== 0o644) {
		fail('source file permissions were not normalized')
	}

	console.log('REFLAXE_OCAML_PACKAGE_ARCHIVE_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, { recursive: true, force: true })
}
