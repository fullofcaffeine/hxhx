#!/usr/bin/env node
const assert = require('assert')
const {evaluateMemoryPlateau} = require('./reflaxe-ocaml-memory-plateau')

const WORD_BYTES = 8
const BASE_LIVE_WORDS = 10_000_000

function gcRows(finalGrowthWords = 3_000, advanceMajorCollections = true) {
	return Array.from({length: 31}, (_, index) => {
		const liveWords = index === 30 ? BASE_LIVE_WORDS + finalGrowthWords : BASE_LIVE_WORDS + index * 100
		return [
			'request-finish', index + 1, 0, 0, 0, 0,
			liveWords + 1_000_000, liveWords, 1_000_000,
			advanceMajorCollections ? 100 + index : 100, 0, liveWords + 2_000_000, 256,
		].join('\t')
	}).join('\n') + '\n'
}

function rssRows({baseline = 850_000, after10 = 860_000, after20 = 870_000, final = 960_000} = {}) {
	const rows = []
	for (let index = 0; index <= 30; index++) {
		const event = index === 0 ? 'baseline' : `request-${index}`
		const total = index === 0 ? baseline : (index === 10 ? after10 : (index === 20 ? after20 : (index === 30 ? final : after10)))
		rows.push(`${event}\t4100\t${Math.floor(total * 0.1)}`)
		rows.push(`${event}\t4200\t${Math.ceil(total * 0.9)}`)
	}
	return rows.join('\n') + '\n'
}

function expectFailure(label, expected, action) {
	let message = ''
	try {
		action()
	} catch (error) {
		message = String(error?.message ?? error)
	}
	assert.ok(message.includes(expected), `${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(message)}`)
}

const noisyRss = evaluateMemoryPlateau(gcRows(), rssRows(), WORD_BYTES)
assert.equal(noisyRss.rssFinalWindowStatus, 'reserved-capacity-observed')
assert.ok(noisyRss.rssFinalWindowGrowthKb > 32 * 1024)
assert.ok(noisyRss.liveFinalWindowGrowthBytes < 32 * 1024 * 1024)

expectFailure('live final-window leak', 'final ten requests retained', () =>
	evaluateMemoryPlateau(gcRows(5_000_000), rssRows(), WORD_BYTES))
expectFailure('unbounded total RSS', 'owned server RSS grew', () =>
	evaluateMemoryPlateau(gcRows(), rssRows({final: 990_000}), WORD_BYTES))
expectFailure('sustained RSS growth', 'two consecutive ten-request windows', () =>
	evaluateMemoryPlateau(gcRows(), rssRows({after10: 870_000, after20: 910_000, final: 950_000}), WORD_BYTES))
expectFailure('missing compacted sample', 'expected 31 compacted GC samples', () =>
	evaluateMemoryPlateau(gcRows().trim().split('\n').slice(1).join('\n') + '\n', rssRows(), WORD_BYTES))
expectFailure('stale collection sample', 'did not record a newer major collection', () =>
	evaluateMemoryPlateau(gcRows(3_000, false), rssRows(), WORD_BYTES))

console.log('REFLAXE_OCAML_MEMORY_PLATEAU_FIXTURES:PASS')
