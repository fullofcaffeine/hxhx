#!/usr/bin/env node
/** Checks fixed report bytes and UTF-8 digests through Haxe Eval and Neko. */
const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const crypto = require('crypto')
const reportJson = require('./ocaml-report-json')

const repoRoot = path.resolve(__dirname, '../..')
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-report-json-'))
const args = [
	'-cp', 'packages/reflaxe.ocaml/src',
	'-cp', 'test/reflaxe_ocaml_report_json/src',
	'--macro', 'nullSafety("reflaxe.ocaml.reports")'
]
function run(command, arguments_) {
	const result = cp.spawnSync(command, arguments_, {
		cwd: repoRoot, encoding: 'utf8', timeout: 60000, shell: false
	})
	assert.ifError(result.error)
	assert.strictEqual(result.status, 0, result.stderr || result.stdout)
	return result.stdout
}

try {
	const interpreted = run('haxe', args.concat('--run', 'ReportJsonFixture'))
	const compiledPath = path.join(temporary, 'report-json.n')
	run('haxe', args.concat('-main', 'ReportJsonFixture', '--neko', compiledPath))
	const compiled = run('neko', [compiledPath])
	assert.strictEqual(compiled, interpreted)
	assert(compiled.endsWith('OCAML_REPORT_JSON:PASS\n'))
	const [expectedBytes, expectedDigest] = compiled.split('\n')
	assert.strictEqual(reportJson(JSON.parse(expectedBytes)), expectedBytes)
	assert.strictEqual('sha256:' + crypto.createHash('sha256').update(expectedBytes, 'utf8').digest('hex'), expectedDigest)
	assert.strictEqual(reportJson({b: 2, a: 1}), '{"a":1,"b":2}')
	console.log('OCAML_REPORT_JSON_EVAL_NEKO:PASS')
} finally {
	fs.rmSync(temporary, {recursive: true, force: true})
}
