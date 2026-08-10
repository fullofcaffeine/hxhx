#!/usr/bin/env node

/** Proves the runtime-use runner's success, timeout, and process cleanup paths. */

'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const {
	parseTimeoutSeconds,
	runCommandWithTimeout,
} = require('./reflaxe-ocaml-runtime-use-authority-runner')

function processExists(pid) {
	try {
		process.kill(pid, 0)
		return true
	} catch (error) {
		if (error.code === 'ESRCH') return false
		throw error
	}
}

async function waitUntilStopped(pid, timeoutMs) {
	const deadline = Date.now() + timeoutMs
	while (processExists(pid) && Date.now() < deadline) {
		await new Promise(resolve => setTimeout(resolve, 20))
	}
	return !processExists(pid)
}

async function main() {
	assert.equal(parseTimeoutSeconds(null), 30)
	assert.equal(parseTimeoutSeconds('9'), 9)
	assert.throws(() => parseTimeoutSeconds('0'), /integer from 1 through 600/)
	assert.throws(() => parseTimeoutSeconds('1.5'), /integer from 1 through 600/)

	const success = await runCommandWithTimeout({
		command: process.execPath,
		args: ['-e', 'console.log("RUNNER_CHILD:PASS")'],
		timeoutMs: 2000,
	})
	assert.equal(success.status, 0, success.stderr)
	assert.equal(success.timedOut, false)
	assert.match(success.stdout, /RUNNER_CHILD:PASS/)

	const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'runtime-use-runner-fixture-'))
	const grandchildPidPath = path.join(temp, 'grandchild.pid')
	const parentScript = [
		"const fs = require('node:fs')",
		"const { spawn } = require('node:child_process')",
		"const child = spawn(process.execPath, ['-e', 'process.on(\"SIGTERM\", () => {}); setInterval(() => {}, 1000)'], { stdio: 'ignore' })",
		"fs.writeFileSync(process.argv[1], String(child.pid))",
		"process.on('SIGTERM', () => {})",
		"setInterval(() => {}, 1000)",
	].join('; ')

	try {
		const timedOut = await runCommandWithTimeout({
			command: process.execPath,
			args: ['-e', parentScript, grandchildPidPath],
			timeoutMs: 150,
			terminationGraceMs: 150,
		})
		assert.equal(timedOut.timedOut, true)
		if (process.platform !== 'win32') {
			assert.equal(timedOut.signal, 'SIGKILL')
		}
		assert.ok(fs.existsSync(grandchildPidPath), 'the child tree should reach the grandchild setup before timeout')
		const grandchildPid = Number(fs.readFileSync(grandchildPidPath, 'utf8'))
		assert.ok(Number.isInteger(grandchildPid) && grandchildPid > 0)
		assert.equal(await waitUntilStopped(timedOut.pid, 2000), true, 'timed-out parent must be stopped')
		assert.equal(await waitUntilStopped(grandchildPid, 2000), true, 'timed-out grandchild must be stopped')
	} finally {
		fs.rmSync(temp, { recursive: true, force: true })
	}

	console.log('REFLAXE_OCAML_RUNTIME_USE_AUTHORITY_RUNNER_FIXTURES:PASS')
}

main().catch(error => {
	console.error(error.stack || error.message)
	process.exitCode = 1
})
