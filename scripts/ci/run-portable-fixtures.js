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

/** Runs tasks concurrently while retaining results in the input order. */
async function runPool(tasks, jobs, runner) {
	const results = new Array(tasks.length)
	let nextIndex = 0
	const workers = Array.from({ length: Math.min(jobs, tasks.length) }, async () => {
		while (nextIndex < tasks.length) {
			const index = nextIndex
			nextIndex += 1
			results[index] = await runner(tasks[index])
		}
	})
	await Promise.all(workers)
	return results
}

/** Captures one fixture process without mixing its output with another worker. */
function runFixture(name) {
	return new Promise(resolve => {
		const startedAt = Date.now()
		const child = cp.spawn('bash', [fixtureRunner], {
			cwd: repoRoot,
			env: {
				...process.env,
				PORTABLE_FIXTURE_ALLOWLIST: name,
				PORTABLE_JOBS: '1',
				PORTABLE_PARALLEL_WORKER: '1'
			},
			stdio: ['ignore', 'pipe', 'pipe']
		})
		let stdout = ''
		let stderr = ''
		let combinedOutput = ''
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
		child.on('error', error => resolve({ name, status: 1, stdout, stderr, combinedOutput, error, durationMs: Date.now() - startedAt }))
		child.on('close', (status, signal) => resolve({
			name,
			status: status ?? 1,
			signal,
			stdout,
			stderr,
			combinedOutput,
			error: null,
			durationMs: Date.now() - startedAt
		}))
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
	const jobs = parseJobs(process.argv.slice(2))
	const fixtures = discoverFixtures(fixtureRoot, process.env.PORTABLE_FIXTURE_ALLOWLIST)
	console.log(`[portable-pool] fixtures=${fixtures.length} jobs=${Math.min(jobs, fixtures.length)}`)
	let completed = 0
	const results = await runPool(fixtures, jobs, async fixture => {
		const result = await runFixture(fixture)
		completed += 1
		console.log(`[portable-pool] completed=${completed}/${fixtures.length} fixture=${fixture} status=${result.status === 0 ? 'pass' : 'fail'} elapsed_ms=${result.durationMs}`)
		return result
	})

	for (const result of results) {
		process.stdout.write(`\n===== portable fixture ${result.name} =====\n`)
		process.stdout.write(result.combinedOutput)
		if (result.error) {
			process.stderr.write(`Unable to start ${result.name}: ${result.error.message}\n`)
		}
		if (result.signal) {
			process.stderr.write(`Fixture ${result.name} ended from signal ${result.signal}.\n`)
		}
	}

	const failed = results.filter(result => result.status !== 0 || result.error)
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
	runPool
}
