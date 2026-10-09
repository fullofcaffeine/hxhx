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

/** Proves actual shell-runner concurrency without touching repository goldens. */
async function verifyParallelGoldenUpdates(repoRoot) {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), 'portable-golden-pool-'))
	const fixtures = path.join(root, 'test/portable/fixtures')
	const bin = path.join(root, 'bin')
	const fixtureNames = ['first', 'second']
	const prepare = () => {
		for (const name of fixtureNames) {
			const dir = path.join(fixtures, name)
			fs.rmSync(dir, { recursive: true, force: true })
			fs.rmSync(path.join(root, `${name}.started`), { force: true })
			fs.mkdirSync(dir, { recursive: true })
			fs.writeFileSync(path.join(dir, 'build.hxml'), '# isolated fake compiler input\n')
			fs.writeFileSync(path.join(dir, 'expected.lowering.json'), JSON.stringify({ original: name }) + '\n')
			fs.writeFileSync(path.join(dir, 'expected.stdout'), name + '\n')
			fs.writeFileSync(path.join(dir, 'test.sh'), 'set -euo pipefail\nprintf checked > .checked\n')
		}
	}
	try {
		fs.mkdirSync(path.join(root, 'scripts/ci'), { recursive: true })
		fs.mkdirSync(bin)
		for (const file of ['scripts/test-portable.sh', 'scripts/ci/run-portable-fixtures.js']) {
			fs.copyFileSync(path.join(repoRoot, file), path.join(root, file))
		}
		const compiler = path.join(bin, 'haxe')
		fs.copyFileSync(path.join(repoRoot, 'scripts/ci/portable-golden-fixture-compiler.js'), compiler)
		fs.chmodSync(compiler, 0o755)
		for (const tool of ['dune', 'ocamlc']) {
			fs.writeFileSync(path.join(bin, tool), '#!/bin/sh\nexit 0\n', { mode: 0o755 })
		}
		const run = (nondeterministic, update = '1') => runOwnedCommand({
			name: 'isolated-golden-update', command: 'bash', args: [path.join(root, 'scripts/test-portable.sh')],
			cwd: root, timeoutMs: 30000, activeChildren: new Map(),
			env: {
				...process.env, PATH: bin + path.delimiter + process.env.PATH, HAXE_BIN: compiler,
				REFLAXE_SOURCE_ROOT: '', PORTABLE_NATIVE_SURFACE_STRICT: '0',
				PORTABLE_FIXTURE_ALLOWLIST: fixtureNames.join(','), PORTABLE_JOBS: '2',
				PORTABLE_PARALLEL_WORKER: '0', PORTABLE_UPDATE_LOWERING_GOLDENS: update,
				PORTABLE_SHARD_INDEX: '0', PORTABLE_SHARD_COUNT: '1', PORTABLE_FIXTURE_TIMEOUT_SECONDS: '20',
				HXHX_PORTABLE_GOLDEN_TEST_ROOT: root, HXHX_PORTABLE_GOLDEN_NONDETERMINISTIC: nondeterministic
			}
		})
		prepare()
		const positive = await run('')
		assert.strictEqual(positive.status, 0, positive.combinedOutput)
		assert.strictEqual(positive.timedOut, false)
		for (const name of fixtureNames) {
			const dir = path.join(fixtures, name)
			assert.strictEqual(fs.readFileSync(path.join(dir, '.compiler-count'), 'utf8'), '2')
			assert.deepStrictEqual(JSON.parse(fs.readFileSync(path.join(dir, 'expected.lowering.json'), 'utf8')),
				{ fixture: name, value: 42 })
			assert.strictEqual(fs.readFileSync(path.join(dir, '.native-ran'), 'utf8'), 'ran\n')
			assert.strictEqual(fs.readFileSync(path.join(dir, '.checked'), 'utf8'), 'checked')
		}
		const normal = await run('', '0')
		assert.strictEqual(normal.status, 0, normal.combinedOutput)
		assert.strictEqual(normal.timedOut, false)
		for (const name of fixtureNames) {
			const dir = path.join(fixtures, name)
			assert.strictEqual(fs.readFileSync(path.join(dir, '.compiler-count'), 'utf8'), '4')
			assert.deepStrictEqual(JSON.parse(fs.readFileSync(path.join(dir, 'expected.lowering.json'), 'utf8')),
				{ fixture: name, value: 42 })
		}
		prepare()
		const golden = path.join(fixtures, 'first/expected.lowering.json')
		const before = fs.readFileSync(golden)
		const negative = await run('first')
		assert.notStrictEqual(negative.status, 0)
		assert.strictEqual(negative.timedOut, false)
		assert.match(negative.combinedOutput, /Lowered semantic report is not deterministic/)
		assert.deepStrictEqual(fs.readFileSync(golden), before, 'nondeterministic output must not replace its golden')
		assert.strictEqual(fs.existsSync(path.join(fixtures, 'first/.native-ran')), false)
		assert.strictEqual(fs.existsSync(path.join(fixtures, 'first/.checked')), false)
	} finally {
		fs.rmSync(root, { recursive: true, force: true })
	}
}

async function main() {
	const repoRoot = path.resolve(__dirname, '../..')
	await verifyParallelGoldenUpdates(repoRoot)
	assert.deepStrictEqual([...parseAllowlist(' be ta,alpha, beta ,,')].sort(), ['alpha', 'beta'])
	assert.strictEqual(parseJobs(['--jobs', '3']), 3)
	assert.throws(() => parseJobs(['--jobs', '0']), /positive integer/)
	assert.strictEqual(parseTimeoutSeconds('9'), 9)
	assert.strictEqual(parseTimeoutSeconds('14400'), 14400)
	assert.throws(() => parseTimeoutSeconds('0'), /integer from 1 through 14400/)
	assert.throws(() => parseTimeoutSeconds('14401'), /integer from 1 through 14400/)
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
			// Repository gates run at reduced scheduling priority on shared hosts.
			// Give the child enough time to start before testing tree cleanup.
			timeoutMs: 2000,
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
