#!/usr/bin/env node
/** Focused deterministic tests for the portable fixture worker pool. */
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const {
	discoverFixtures,
	parseAllowlist,
	parseJobs,
	parseShard,
	parseTimeoutSeconds,
	runOwnedCommand,
	runPool,
	selectShard
} = require('./run-portable-fixtures')

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
	const repoRoot = path.resolve(__dirname, '../..')
	assert.deepStrictEqual([...parseAllowlist(' be ta,alpha, beta ,,')].sort(), ['alpha', 'beta'])
	assert.strictEqual(parseJobs(['--jobs', '3']), 3)
	assert.throws(() => parseJobs(['--jobs', '0']), /positive integer/)
	assert.strictEqual(parseTimeoutSeconds('9'), 9)
	assert.throws(() => parseTimeoutSeconds('0'), /integer from 1 through 3600/)
	assert.deepStrictEqual(parseShard(null, null), { index: 0, count: 1 })
	assert.deepStrictEqual(parseShard('2', '3'), { index: 2, count: 3 })
	assert.throws(() => parseShard('2', '2'), /zero-based shard/)
	assert.throws(() => parseShard('', '2'), /zero-based shard/)
	const shardInput = ['a', 'b', 'c', 'd', 'e']
	const firstShard = selectShard(shardInput, { index: 0, count: 3 })
	const secondShard = selectShard(shardInput, { index: 1, count: 3 })
	const thirdShard = selectShard(shardInput, { index: 2, count: 3 })
	assert.deepStrictEqual(firstShard, ['a', 'd'])
	assert.deepStrictEqual(secondShard, ['b', 'e'])
	assert.deepStrictEqual(thirdShard, ['c'])
	assert.deepStrictEqual([...firstShard, ...secondShard, ...thirdShard].sort(), shardInput)
	const discoveredFixtures = discoverFixtures(path.join(repoRoot, 'test/portable/fixtures'), '')
	const discoveredShards = [0, 1, 2].map(index => selectShard(discoveredFixtures, { index, count: 3 }))
	const selectedFixtures = discoveredShards.flat()
	assert.strictEqual(new Set(selectedFixtures).size, discoveredFixtures.length)
	assert.deepStrictEqual(selectedFixtures.sort(), discoveredFixtures)
	assert.ok(Math.max(...discoveredShards.map(shard => shard.length)) - Math.min(...discoveredShards.map(shard => shard.length)) <= 1)

	let active = 0
	let maximumActive = 0
	const starts = []
	const results = await runPool(['slow', 'fast', 'last'], 2, async task => {
		starts.push(task)
		active += 1
		maximumActive = Math.max(maximumActive, active)
		await new Promise(resolve => setTimeout(resolve, task === 'slow' ? 20 : 1))
		active -= 1
		return `${task}:done`
	})

	assert.strictEqual(maximumActive, 2)
	assert.deepStrictEqual(starts.slice(0, 2), ['slow', 'fast'])
	assert.deepStrictEqual(results, ['slow:done', 'fast:done', 'last:done'])

	const failFastStarts = []
	let cleanupCalls = 0
	const failFastResults = await runPool(['fail', 'active', 'never'], 2, async task => {
		failFastStarts.push(task)
		await new Promise(resolve => setTimeout(resolve, task === 'fail' ? 1 : 20))
		return { task, failed: task === 'fail' }
	}, {
		isFailure: result => result.failed,
		onFailure: async () => {
			cleanupCalls += 1
		}
	})
	assert.deepStrictEqual(failFastStarts, ['fail', 'active'])
	assert.strictEqual(cleanupCalls, 1)
	assert.deepStrictEqual(failFastResults.map(result => result.task), ['fail', 'active'])

	const workflow = fs.readFileSync(path.join(repoRoot, '.github/workflows/stdlib-portable-lite.yml'), 'utf8')
	assert.match(workflow, /PORTABLE_JOBS: "4"/)
	assert.match(workflow, /PORTABLE_FIXTURE_TIMEOUT_SECONDS: "2100"/)
	assert.match(workflow, /PORTABLE_SHARD_COUNT: "3"/)
	assert.match(workflow, /PORTABLE_SHARD_INDEX: "\$\{\{ matrix\.shard_index \}\}"/)
	assert.match(workflow, /shard_index: \[0, 1, 2\]/)
	assert.match(workflow, /name: Stdlib portable tier1 \(shard \$\{\{ matrix\.shard_index \}\}\/3\)/)
	assert.doesNotMatch(workflow, /PORTABLE_FIXTURE_ALLOWLIST/)

	const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'portable-pool-fixture-'))
	const grandchildPidPath = path.join(temp, 'grandchild.pid')
	const parentScript = [
		"const fs = require('fs')",
		"const { spawn } = require('child_process')",
		"const child = spawn(process.execPath, ['-e', 'process.on(\"SIGTERM\", () => {}); setInterval(() => {}, 1000)'], { stdio: 'ignore' })",
		"fs.writeFileSync(process.argv[1], String(child.pid))",
		"process.on('SIGTERM', () => {})",
		"setInterval(() => {}, 1000)"
	].join('; ')
	try {
		const activeChildren = new Map()
		const timedOut = await runOwnedCommand({
			name: 'timeout-fixture',
			command: process.execPath,
			args: ['-e', parentScript, grandchildPidPath],
			cwd: process.cwd(),
			env: process.env,
			timeoutMs: 150,
			activeChildren
		})
		assert.strictEqual(timedOut.timedOut, true)
		assert.strictEqual(activeChildren.size, 0)
		assert.ok(fs.existsSync(grandchildPidPath), 'the timeout fixture should start its grandchild')
		const grandchildPid = Number(fs.readFileSync(grandchildPidPath, 'utf8'))
		assert.strictEqual(await waitUntilStopped(grandchildPid, 2000), true, 'the timed-out grandchild must stop')
	} finally {
		fs.rmSync(temp, { recursive: true, force: true })
	}
	console.log('PORTABLE_FIXTURE_POOL:PASS')
}

main().catch(error => {
	console.error(error && error.stack ? error.stack : error)
	process.exit(1)
})
