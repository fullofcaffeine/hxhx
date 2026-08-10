#!/usr/bin/env node

/**
 * Runs the runtime-use authority checks with one deadline per Haxe process.
 *
 * These checks deliberately ask Haxe 4.3.7 to run null-safety over the whole
 * `reflaxe.ocaml` package. If a future source shape makes that compiler pass
 * pathological again, this runner stops the process and every child it owns
 * instead of leaving an unbounded CI job behind.
 */

'use strict'

const path = require('node:path')
const { spawn, spawnSync } = require('node:child_process')

const REPO_ROOT = path.resolve(__dirname, '..', '..')
const DEFAULT_TIMEOUT_SECONDS = 30
const TERMINATION_GRACE_MS = 500

const phases = [
	{
		name: 'runtime-use-authority',
		fixturePath: 'test/reflaxe_ocaml_runtime_use_authority/src',
		main: 'RuntimeUseAuthorityFixture',
	},
	{
		name: 'checked-generated-text',
		fixturePath: 'test/reflaxe_ocaml_checked_generated_text/src',
		main: 'CheckedGeneratedTextFixture',
	},
	{
		name: 'type-registry-generated-text',
		fixturePath: 'test/reflaxe_ocaml_type_registry_generated_text/src',
		main: 'TypeRegistryGeneratedTextFixture',
	},
]

/** Converts the optional environment setting into a safe per-phase deadline. */
function parseTimeoutSeconds(value, fallback = DEFAULT_TIMEOUT_SECONDS) {
	if (value == null || value === '') return fallback
	const parsed = Number(value)
	if (!Number.isInteger(parsed) || parsed < 1 || parsed > 600) {
		throw new Error('REFLAXE_OCAML_RUNTIME_USE_TIMEOUT_SECONDS must be an integer from 1 through 600.')
	}
	return parsed
}

/** Signals only the spawned process tree, never an unrelated repository job. */
function signalOwnedProcessTree(child, signal) {
	if (child.pid == null) return
	try {
		if (process.platform === 'win32') {
			// Windows has no POSIX process groups. Keep the child alive during the
			// grace period, then ask taskkill to remove it and all descendants.
			if (signal === 'SIGTERM') return
			const result = spawnSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], {
				encoding: 'utf8',
				windowsHide: true,
			})
			if (result.status !== 0 && result.status !== 128) {
				throw new Error((result.stderr || result.stdout || `taskkill exited ${result.status}`).trim())
			}
		} else {
			process.kill(-child.pid, signal)
		}
	} catch (error) {
		if (error.code !== 'ESRCH') throw error
	}
}

/**
 * Runs one command and resolves only after its owned process tree is cleaned up.
 *
 * A POSIX child starts in a new process group. On timeout the complete group
 * receives TERM, followed by KILL after a short grace period. Windows uses the
 * equivalent taskkill tree operation after that grace period. This covers Haxe
 * today and any compiler subprocess it may gain later.
 */
function runCommandWithTimeout({
	command,
	args,
	cwd = REPO_ROOT,
	env = process.env,
	timeoutMs,
	terminationGraceMs = TERMINATION_GRACE_MS,
}) {
	return new Promise(resolve => {
		const startedAt = Date.now()
		const child = spawn(command, args, {
			cwd,
			env,
			detached: process.platform !== 'win32',
			stdio: ['ignore', 'pipe', 'pipe'],
		})
		let stdout = ''
		let stderr = ''
		let timedOut = false
		let cleanupFinished = false
		let closeResult = null
		let settled = false

		child.stdout.on('data', chunk => {
			stdout += chunk
		})
		child.stderr.on('data', chunk => {
			stderr += chunk
		})

		const finishIfReady = () => {
			if (settled || closeResult == null || (timedOut && !cleanupFinished)) return
			settled = true
			resolve({
				...closeResult,
				pid: child.pid,
				stdout,
				stderr,
				timedOut,
				elapsedMs: Date.now() - startedAt,
			})
		}

		const deadline = setTimeout(() => {
			timedOut = true
			try {
				signalOwnedProcessTree(child, 'SIGTERM')
			} catch (error) {
				stderr += `\nFailed to terminate owned process group: ${error.message}\n`
			}
			setTimeout(() => {
				try {
					signalOwnedProcessTree(child, 'SIGKILL')
				} catch (error) {
					stderr += `\nFailed to kill owned process group: ${error.message}\n`
				}
				cleanupFinished = true
				finishIfReady()
			}, terminationGraceMs)
		}, timeoutMs)

		child.once('error', error => {
			closeResult = { status: null, signal: null, spawnError: error }
			clearTimeout(deadline)
			finishIfReady()
		})
		child.once('close', (status, signal) => {
			if (closeResult == null) closeResult = { status, signal, spawnError: null }
			clearTimeout(deadline)
			finishIfReady()
		})
	})
}

function haxeArguments(phase) {
	return [
		'-cp',
		'packages/reflaxe.ocaml/src',
		'-cp',
		phase.fixturePath,
		'-D',
		'reflaxe_runtime',
		'--macro',
		'nullSafety("reflaxe.ocaml")',
		'--run',
		phase.main,
	]
}

async function main() {
	let timeoutSeconds
	try {
		timeoutSeconds = parseTimeoutSeconds(process.env.REFLAXE_OCAML_RUNTIME_USE_TIMEOUT_SECONDS)
	} catch (error) {
		console.error(`RUNTIME_USE_AUTHORITY_RUNNER:ERROR ${error.message}`)
		process.exitCode = 2
		return
	}

	const haxe = process.env.HAXE_BIN || 'haxe'
	for (const phase of phases) {
		const result = await runCommandWithTimeout({
			command: haxe,
			args: haxeArguments(phase),
			timeoutMs: timeoutSeconds * 1000,
		})
		process.stdout.write(result.stdout)
		process.stderr.write(result.stderr)

		if (result.timedOut) {
			console.error(`RUNTIME_USE_AUTHORITY_PHASE:TIMEOUT phase=${phase.name} elapsed_ms=${result.elapsedMs} budget_seconds=${timeoutSeconds}`)
			process.exitCode = 124
			return
		}
		if (result.spawnError != null) {
			console.error(`RUNTIME_USE_AUTHORITY_PHASE:ERROR phase=${phase.name} message=${result.spawnError.message}`)
			process.exitCode = 1
			return
		}
		if (result.status !== 0) {
			console.error(`RUNTIME_USE_AUTHORITY_PHASE:FAIL phase=${phase.name} status=${result.status} signal=${result.signal || 'none'}`)
			process.exitCode = result.status || 1
			return
		}
		console.log(`RUNTIME_USE_AUTHORITY_PHASE:PASS phase=${phase.name} elapsed_ms=${result.elapsedMs} budget_seconds=${timeoutSeconds}`)
	}
	console.log('RUNTIME_USE_AUTHORITY_RUNNER:PASS')
}

module.exports = {
	parseTimeoutSeconds,
	runCommandWithTimeout,
}

if (require.main === module) {
	main().catch(error => {
		console.error(`RUNTIME_USE_AUTHORITY_RUNNER:ERROR ${error.stack || error.message}`)
		process.exitCode = 1
	})
}
