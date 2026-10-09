#!/usr/bin/env node
/** Fake compiler for the isolated golden-update runner test; never a real build tool. */
const assert = require('assert')
const fs = require('fs')
const path = require('path')

async function main() {
	const root = process.env.HXHX_PORTABLE_GOLDEN_TEST_ROOT
	assert.ok(root, 'the fake compiler requires its isolated test root')
	const name = path.basename(process.cwd())
	assert.ok(['first', 'second'].includes(name), 'unexpected fake fixture')
	assert.strictEqual(fs.realpathSync(process.cwd()), fs.realpathSync(path.join(root, 'test/portable/fixtures', name)))
	assert.ok(process.argv.includes('build.hxml'))
	const counterPath = '.compiler-count'
	const count = fs.existsSync(counterPath) ? Number(fs.readFileSync(counterPath, 'utf8')) + 1 : 1
	fs.writeFileSync(counterPath, String(count))
	if (count === 1) {
		fs.writeFileSync(path.join(root, `${name}.started`), '')
		const deadline = Date.now() + 10000
		while (!['first', 'second'].every(peer => fs.existsSync(path.join(root, `${peer}.started`)))) {
			assert.ok(Date.now() < deadline, 'the peer compiler did not start concurrently')
			await new Promise(resolve => setTimeout(resolve, 20))
		}
	}
	fs.mkdirSync('out/_build/default', { recursive: true })
	const value = process.env.HXHX_PORTABLE_GOLDEN_NONDETERMINISTIC === name ? count : 42
	fs.writeFileSync('out/ocaml_lowering_report.json', JSON.stringify({ fixture: name, value }) + '\n')
	fs.writeFileSync('out/_build/default/out.exe',
		`#!/bin/sh\nprintf '%s\\n' '${name}'\nprintf '%s\\n' ran > "$(dirname "$0")/../../../.native-ran"\n`, { mode: 0o755 })
}

main().catch(error => {
	console.error(error.stack || error)
	process.exitCode = 1
})
