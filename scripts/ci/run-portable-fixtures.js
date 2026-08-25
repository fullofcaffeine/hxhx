#!/usr/bin/env node
/**
 * Runs independent portable OCaml fixtures with a small, bounded worker pool.
 *
 * Each worker starts the existing fail-closed shell runner for exactly one
 * fixture. Output is retained per fixture and replayed in sorted fixture order,
 * so concurrent execution does not make the detailed CI log hard to review.
 */
const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const fixtureRoot = path.join(repoRoot, 'test/portable/fixtures')
const fixtureRunner = path.join(repoRoot, 'scripts/test-portable.sh')
const defaultFixtureTimeoutSeconds = 30 * 60
const terminationGraceMs = 500

function fail(message) {
	throw new Error(message)
}

/** Parses the comma-separated fixture filter used by the shell runner. */
function parseAllowlist(value) {
	return new Set(String(value || '')
		.split(',')
		.map(entry => entry.replace(/\s/g, ''))
		.filter(Boolean))
}

/** Returns runnable fixture names in the same stable order as the shell loop. */
function discoverFixtures(root, allowlistValue) {
	const allowlist = parseAllowlist(allowlistValue)
	const fixtures = fs.readdirSync(root, { withFileTypes: true })
		.filter(entry => entry.isDirectory())
		.map(entry => entry.name)
		.filter(name => fs.existsSync(path.join(root, name, 'build.hxml')))
		.filter(name => allowlist.size === 0 || allowlist.has(name))
		.sort()
	if (fixtures.length === 0) {
		fail(allowlist.size === 0
			? `No portable fixtures with build.hxml were found under ${root}`
			: `No matching fixtures for PORTABLE_FIXTURE_ALLOWLIST=${allowlistValue}`)
	}
	return fixtures
}

/**
 * Runs tasks concurrently while retaining results in the input order.
 *
 * When `isFailure` identifies a failed result, workers stop taking new tasks
 * and `onFailure` can terminate work that is already in flight.
 */
async function runPool(tasks, jobs, runner, { isFailure = () => false, onFailure = async () => {} } = {}) {
	const results = new Array(tasks.length)
	let nextIndex = 0
	let stopped = false
	let failureHandled = false
	const workers = Array.from({ length: Math.min(jobs, tasks.length) }, async () => {
		while (!stopped && nextIndex < tasks.length) {
			const index = nextIndex
			nextIndex += 1
			const result = await runner(tasks[index])
			results[index] = result
			if (isFailure(result)) {
				stopped = true
				if (!failureHandled) {
					failureHandled = true
					await onFailure(result)
				}
			}
		}
	})
	await Promise.all(workers)
	return results.filter(result => result !== undefined)
}

/** Converts the fixture deadline setting into a safe number of seconds. */
function parseTimeoutSeconds(value) {
	const raw = value == null || value === '' ? String(defaultFixtureTimeoutSeconds) : String(value)
	if (!/^[1-9][0-9]*$/.test(raw) || Number(raw) > 3600) {
		fail(`PORTABLE_FIXTURE_TIMEOUT_SECONDS must be an integer from 1 through 3600, got: ${raw}`)
	}
	return Number(raw)
}

/** Signals only one child process tree owned by this runner. */
function signalOwnedProcessTree(child, signal) {
	if (child.pid == null) return
	try {
		if (process.platform === 'win32') {
			if (signal === 'SIGTERM') return
			const result = cp.spawnSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], {
				encoding: 'utf8',
				windowsHide: true
			})
			if (result.status !== 0 && result.status !== 128) {
				fail((result.stderr || result.stdout || `taskkill exited ${result.status}`).trim())
			}
		} else {
			process.kill(-child.pid, signal)
		}
	} catch (error) {
		if (error.code === 'ESRCH') return
		try {
			child.kill(signal)
		} catch (fallbackError) {
			if (fallbackError.code !== 'ESRCH') throw error
		}
	}
}

/** Stops all fixture process trees and waits for their parent processes. */
async function terminateActiveFixtures(activeChildren, reason) {
	const entries = [...activeChildren.values()]
	if (entries.length === 0) return
	console.error(`[portable-pool] stopping=${entries.length} reason=${reason}`)
	for (const entry of entries) {
		entry.cancelledReason = reason
		signalOwnedProcessTree(entry.child, 'SIGTERM')
	}
	await new Promise(resolve => setTimeout(resolve, terminationGraceMs))
	for (const entry of entries) signalOwnedProcessTree(entry.child, 'SIGKILL')
	await Promise.all(entries.map(entry => entry.closed))
}

/** Captures one owned process without mixing its output with another worker. */
function runOwnedCommand({ name, command, args, cwd, env, timeoutMs, activeChildren }) {
	return new Promise(resolve => {
		const startedAt = Date.now()
		const child = cp.spawn(command, args, {
			cwd,
			env,
			detached: process.platform !== 'win32',
			stdio: ['ignore', 'pipe', 'pipe']
		})
		let stdout = ''
		let stderr = ''
		let combinedOutput = ''
		let timedOut = false
		let settled = false
		let cleanupFinished = true
		let closeResult = null
		child.stdout.setEncoding('utf8')
		child.stderr.setEncoding('utf8')
		child.stdout.on('data', chunk => {
			stdout += chunk
			combinedOutput += chunk
		})
		child.stderr.on('data', chunk => {
			stderr += chunk
			combinedOutput += chunk
		})
		const deadline = setTimeout(() => {
			timedOut = true
			cleanupFinished = false
			signalOwnedProcessTree(child, 'SIGTERM')
			setTimeout(() => {
				signalOwnedProcessTree(child, 'SIGKILL')
				cleanupFinished = true
				finishIfReady()
			}, terminationGraceMs)
		}, timeoutMs)
		const finishIfReady = () => {
			if (settled || closeResult == null || !cleanupFinished) return
			settled = true
			clearTimeout(deadline)
			activeChildren.delete(child.pid)
			if (!timedOut && closeResult.status !== 0) signalOwnedProcessTree(child, 'SIGKILL')
			resolve({
				name,
				status: closeResult.status ?? 1,
				signal: closeResult.signal,
				stdout,
				stderr,
				combinedOutput,
				error: closeResult.error,
				cancelledReason: ownership.cancelledReason,
				timedOut,
				durationMs: Date.now() - startedAt
			})
		}
		const closed = new Promise(closedResolve => child.once('close', closedResolve))
		const ownership = { child, closed, cancelledReason: null }
		activeChildren.set(child.pid, ownership)
		child.once('error', error => {
			closeResult = { status: 1, signal: null, error }
			clearTimeout(deadline)
			finishIfReady()
		})
		child.once('close', (status, signal) => {
			closeResult = { status, signal, error: null }
			clearTimeout(deadline)
			finishIfReady()
		})
	})
}

/** Runs one portable fixture with a deadline and owned process-tree cleanup. */
function runFixture(name, timeoutMs, activeChildren) {
	return runOwnedCommand({
		name,
		command: 'bash',
		args: [fixtureRunner],
		cwd: repoRoot,
		env: {
			...process.env,
			PORTABLE_FIXTURE_ALLOWLIST: name,
			PORTABLE_JOBS: '1',
			PORTABLE_PARALLEL_WORKER: '1'
		},
		timeoutMs,
		activeChildren
	})
}

function parseJobs(argv) {
	const index = argv.indexOf('--jobs')
	const raw = index === -1 ? process.env.PORTABLE_JOBS || '2' : argv[index + 1]
	if (!/^[1-9][0-9]*$/.test(String(raw || ''))) {
		fail(`--jobs must be a positive integer, got: ${raw}`)
	}
	return Number(raw)
}

async function main() {
	const suiteStartedAt = Date.now()
	const jobs = parseJobs(process.argv.slice(2))
	const timeoutSeconds = parseTimeoutSeconds(process.env.PORTABLE_FIXTURE_TIMEOUT_SECONDS)
	const fixtures = discoverFixtures(fixtureRoot, process.env.PORTABLE_FIXTURE_ALLOWLIST)
	const activeChildren = new Map()
	console.log(`[portable-pool] fixtures=${fixtures.length} jobs=${Math.min(jobs, fixtures.length)} fixture_timeout_seconds=${timeoutSeconds}`)
	let shuttingDown = false
	const stopForSignal = signal => {
		if (shuttingDown) return
		shuttingDown = true
		terminateActiveFixtures(activeChildren, `received_${signal}`)
			.then(() => process.exit(signal === 'SIGINT' ? 130 : 143))
			.catch(error => {
				console.error(error && error.stack ? error.stack : error)
				process.exit(1)
			})
	}
	process.once('SIGINT', stopForSignal)
	process.once('SIGTERM', stopForSignal)
	let completed = 0
	const results = await runPool(fixtures, jobs, async fixture => {
		const result = await runFixture(fixture, timeoutSeconds * 1000, activeChildren)
		completed += 1
		const status = result.cancelledReason ? 'cancelled' : result.timedOut ? 'timeout' : result.status === 0 ? 'pass' : 'fail'
		console.log(`[portable-pool] completed=${completed}/${fixtures.length} fixture=${fixture} status=${status} elapsed_ms=${result.durationMs}`)
		return result
	}, {
		isFailure: result => result.status !== 0 || result.error || result.timedOut,
		onFailure: result => terminateActiveFixtures(activeChildren, `fixture_${result.name}_failed`)
	})
	if (shuttingDown) return
	process.removeListener('SIGINT', stopForSignal)
	process.removeListener('SIGTERM', stopForSignal)

	for (const result of results) {
		process.stdout.write(`\n===== portable fixture ${result.name} =====\n`)
		process.stdout.write(result.combinedOutput)
		if (result.error) {
			process.stderr.write(`Unable to start ${result.name}: ${result.error.message}\n`)
		}
		if (result.signal) {
			process.stderr.write(`Fixture ${result.name} ended from signal ${result.signal}.\n`)
		}
		if (result.timedOut) {
			process.stderr.write(`Fixture ${result.name} exceeded its ${timeoutSeconds}-second deadline.\n`)
		}
		if (result.cancelledReason) {
			process.stderr.write(`Fixture ${result.name} was cancelled because ${result.cancelledReason}.\n`)
		}
	}

	const workerElapsedMs = results.reduce((total, result) => total + result.durationMs, 0)
	console.log(`[portable-pool] summary started=${results.length}/${fixtures.length} passed=${results.filter(result => result.status === 0).length} worker_elapsed_ms=${workerElapsedMs} wall_elapsed_ms=${Date.now() - suiteStartedAt}`)
	const failed = results.filter(result => !result.cancelledReason && (result.status !== 0 || result.error || result.timedOut))
	if (failed.length > 0) {
		fail(`Portable fixtures failed: ${failed.map(result => result.name).join(', ')}`)
	}
	console.log('✓ Portable conformance OK')
}

if (require.main === module) {
	main().catch(error => {
		console.error(error && error.stack ? error.stack : error)
		process.exit(1)
	})
}

module.exports = {
	discoverFixtures,
	parseAllowlist,
	parseJobs,
	parseTimeoutSeconds,
	runOwnedCommand,
	runPool
}
