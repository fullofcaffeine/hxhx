#!/usr/bin/env node
/** Proves haxelib compiler options cannot masquerade as installed library paths. */
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { resolvedLibraryPaths } = require('./reflaxe-ocaml-perf-platform')

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-perf-platform-fixture-'))
try {
	const target = path.join(tempRoot, 'target')
	const framework = path.join(tempRoot, 'framework')
	fs.mkdirSync(target)
	fs.mkdirSync(framework)
	const output = [
		target,
		framework,
		'-D reflaxe_ocaml=1',
		'--macro nullSafety("reflaxe.ocaml")',
		''
	].join('\n')
	assert.deepStrictEqual(resolvedLibraryPaths(output, tempRoot), [fs.realpathSync(target), fs.realpathSync(framework)])
	console.log('REFLAXE_OCAML_PERF_PLATFORM_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, { recursive: true, force: true })
}
