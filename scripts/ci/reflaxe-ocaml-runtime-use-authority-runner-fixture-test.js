#!/usr/bin/env node

/** Proves the runtime-use runner's success, timeout, and process cleanup paths. */

'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { mock } = require('node:test')
// Keep startup observation bounded by real time while only the runner clock is controlled.
const { setTimeout: realSetTimeout, clearTimeout: realClearTimeout } = require('node:timers')
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

/** Observes both installed signal handlers without assuming a process startup speed. */
function watchReadiness(directory, readyPath, timeoutMs) {
	let close = () => {}
	const ready = new Promise((resolve, reject) => {
		const watcher = fs.watch(directory, () => {
			if (!fs.existsSync(readyPath)) return
			close()
			resolve()
		})
		const deadline = realSetTimeout(() => {
			close()
			reject(new Error('process tree did not become ready before the startup deadline'))
		}, timeoutMs)
		close = () => {
			watcher.close()
			realClearTimeout(deadline)
		}
		watcher.once('error', error => {
			close()
			reject(error)
		})
	})
	return { ready, close: () => close() }
}

/** Advances the real runner's timeout and grace period only after the chosen startup outcome. */
async function assertTreeCleanup({ startupDelay, startupBudget, expectReady }) {
	const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'runtime-use-runner-fixture-'))
	const readyPath = path.join(temp, 'ready.json')
	const watch = watchReadiness(temp, readyPath, startupBudget)
	let result
	try {
		mock.timers.enable({ apis: ['setTimeout'] })
		const pending = runCommandWithTimeout({
			command: process.execPath,
			args: [path.resolve(__dirname, '../../test/reflaxe_ocaml_runtime_use_authority_runner/child.js'), 'parent', readyPath, startupDelay],
			timeoutMs: 150,
			terminationGraceMs: 150,
		})
		try {
			if (expectReady) await watch.ready
			else await assert.rejects(watch.ready, /startup deadline/)
		} finally {
			watch.close()
			// Every outcome, including failed startup, must terminate the owned tree.
			mock.timers.tick(150)
			mock.timers.tick(150)
			try {
				result = await pending
			} finally {
				mock.timers.reset()
			}
		}
		assert.equal(result.timedOut, true)
		if (expectReady && process.platform !== 'win32') assert.equal(result.signal, 'SIGKILL')
		assert.equal(await waitUntilStopped(result.pid, 2000), true, 'timed-out parent must be stopped')
		if (expectReady) {
			const record = JSON.parse(fs.readFileSync(readyPath, 'utf8'))
			assert.equal(record.parent, result.pid)
			assert.ok(Number.isInteger(record.child) && record.child > 0)
			assert.equal(await waitUntilStopped(record.child, 2000), true, 'ready grandchild must be stopped')
		} else if (fs.existsSync(readyPath + '.created')) {
			const child = Number(fs.readFileSync(readyPath + '.created', 'utf8'))
			assert.ok(Number.isInteger(child) && child > 0)
			assert.equal(await waitUntilStopped(child, 2000), true, 'unready grandchild must be stopped')
		}
	} finally {
		watch.close()
		mock.timers.reset()
		fs.rmSync(temp, { recursive: true, force: true })
	}
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

	await assertTreeCleanup({ startupDelay: '0', startupBudget: 5000, expectReady: true })
	await assertTreeCleanup({ startupDelay: '350', startupBudget: 5000, expectReady: true })
	await assertTreeCleanup({ startupDelay: 'never', startupBudget: 25, expectReady: false })

	// A separate real-clock case preserves proof that the production deadline needs no readiness signal.
	const realTimeout = await runCommandWithTimeout({
		command: process.execPath,
		args: ['-e', 'setInterval(() => {}, 1000)'],
		timeoutMs: 25,
		terminationGraceMs: 50,
	})
	assert.equal(realTimeout.timedOut, true)
	assert.equal(await waitUntilStopped(realTimeout.pid, 2000), true, 'real deadline must stop a child without readiness')

	console.log('REFLAXE_OCAML_RUNTIME_USE_AUTHORITY_RUNNER_FIXTURES:PASS')
}

main().catch(error => {
	console.error(error.stack || error.message)
	process.exitCode = 1
})
