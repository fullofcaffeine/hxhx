#!/usr/bin/env node
/** Focused deterministic tests for the portable fixture worker pool. */
const assert = require('assert')
const {
	parseAllowlist,
	parseJobs,
	runPool
} = require('./run-portable-fixtures')

async function main() {
	assert.deepStrictEqual([...parseAllowlist(' be ta,alpha, beta ,,')].sort(), ['alpha', 'beta'])
	assert.strictEqual(parseJobs(['--jobs', '3']), 3)
	assert.throws(() => parseJobs(['--jobs', '0']), /positive integer/)

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
	console.log('PORTABLE_FIXTURE_POOL:PASS')
}

main().catch(error => {
	console.error(error && error.stack ? error.stack : error)
	process.exit(1)
})
