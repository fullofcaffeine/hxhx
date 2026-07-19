#!/usr/bin/env node
/** Proves the real source-checkout CLI entrypoint and stable JSON contract. */
const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const haxeArgs = [
	'-cp', 'packages/reflaxe.ocaml/src',
	'--macro', 'nullSafety("reflaxe.ocaml")',
	'--run', 'reflaxe.ocaml.tooling.ReflaxeOcamlRun'
]

function run(args, options = {}) {
	return cp.spawnSync('haxe', haxeArgs.concat(args), {
		cwd: repoRoot,
		env: {...process.env, ...(options.env || {})},
		encoding: 'utf8',
		shell: false
	})
}

function parseReport(result) {
	assert.strictEqual(result.status, 0, result.stderr || result.stdout)
	return JSON.parse(result.stdout)
}

const source = parseReport(run(['doctor', '--json', '--require', 'source']))
assert.strictEqual(source.schemaVersion, 1)
assert.strictEqual(source.packageName, 'reflaxe.ocaml')
assert.strictEqual(source.summary.requestedCapability, 'source')
assert.strictEqual(source.summary.ready, true)
assert.strictEqual(source.summary.exitCode, 0)
assert.strictEqual(source.capabilities.sourceGeneration, true)
assert(source.checks.some(check => check.id === 'runtime-manifest' && check.status === 'skip'))
const missingHxhx = source.checks.find(check => check.id === 'hxhx')
if (missingHxhx && missingHxhx.status === 'skip') {
	assert.strictEqual(missingHxhx.version, null)
}

const projectRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-doctor-project-'))
try {
	const haxelibShape = parseReport(run(['doctor', '--json', projectRoot], {
		env: {HAXELIB_RUN: '1', HAXELIB_RUN_NAME: 'reflaxe.ocaml'}
	}))
	assert.strictEqual(path.resolve(haxelibShape.projectRoot), path.resolve(projectRoot))
} finally {
	fs.rmSync(projectRoot, {recursive: true, force: true})
}

const invalid = run(['doctor', '--require', 'everything'])
assert.strictEqual(invalid.status, 2)
assert(invalid.stderr.includes('Unknown required capability'))

const version = run(['version'])
assert.strictEqual(version.status, 0)
assert(/^reflaxe\.ocaml \d+\.\d+\.\d+/.test(version.stdout.trim()))

const watchHelp = run(['watch', '--help'])
assert.strictEqual(watchHelp.status, 0)
assert(watchHelp.stdout.includes('Watch and rebuild a reflaxe.ocaml project'))
assert(watchHelp.stdout.includes('--watch-path <path>'))

const partialPollInterval = run(['watch', '--poll-ms', '10ms'])
assert.strictEqual(partialPollInterval.status, 2)
assert(partialPollInterval.stderr.includes('--poll-ms needs a positive integer'))

const oneShotBuildLimit = run(['build', '--max-builds', '2'])
assert.strictEqual(oneShotBuildLimit.status, 2)
assert(oneShotBuildLimit.stderr.includes('--max-builds is only meaningful'))

console.log('REFLAXE_OCAML_DOCTOR_CLI_FIXTURE:PASS')
