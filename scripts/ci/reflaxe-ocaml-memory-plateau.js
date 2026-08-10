#!/usr/bin/env node
/**
 * Decides whether repeated compiler-server requests retain more memory.
 *
 * The OCaml evaluator records `live_words` after it forces a full collection
 * and compacts its heap. Those words describe objects that are still reachable
 * by the compiler. Process RSS is broader: it also includes memory pages that
 * the allocator or operating system keeps ready for reuse. A short RSS rise is
 * therefore reported, but only live objects decide the final-ten plateau.
 * Total RSS still has a 128 MiB ceiling so memory outside the OCaml heap cannot
 * grow without a bound.
 */
const fs = require('fs')

const EXPECTED_REQUESTS = 30
const OVERALL_LIMIT_BYTES = 128 * 1024 * 1024
const FINAL_WINDOW_LIMIT_BYTES = 32 * 1024 * 1024
const OVERALL_RSS_LIMIT_KB = 128 * 1024
const FINAL_WINDOW_RSS_OBSERVATION_KB = 32 * 1024

function fail(message) {
	throw new Error(message)
}

function integer(value, label, {positive = false} = {}) {
	if (!/^[0-9]+$/.test(value)) fail(`${label} is not a non-negative integer: ${JSON.stringify(value)}`)
	const parsed = Number(value)
	if (!Number.isSafeInteger(parsed) || (positive && parsed === 0)) {
		fail(`${label} is outside the supported integer range: ${JSON.stringify(value)}`)
	}
	return parsed
}

function parseGcRows(contents) {
	const lines = contents.trim().length === 0 ? [] : contents.trim().split('\n')
	if (lines.length !== EXPECTED_REQUESTS + 1) {
		fail(`expected 31 compacted GC samples (one baseline plus thirty requests), found ${lines.length}`)
	}
	return lines.map((line, index) => {
		const fields = line.split('\t')
		if (fields.length !== 13) fail(`compacted GC sample ${index} has ${fields.length} fields instead of 13`)
		if (fields[0] !== 'request-finish') fail(`compacted GC sample ${index} has unexpected event ${JSON.stringify(fields[0])}`)
		const row = {
			requestSequence: integer(fields[1], `GC sample ${index} request sequence`),
			entryCount: integer(fields[2], `GC sample ${index} entry count`),
			payloadBytes: integer(fields[3], `GC sample ${index} payload bytes`),
			estimatedOverheadBytes: integer(fields[4], `GC sample ${index} estimated overhead bytes`),
			activeLeases: integer(fields[5], `GC sample ${index} active leases`),
			heapWords: integer(fields[6], `GC sample ${index} heap words`),
			liveWords: integer(fields[7], `GC sample ${index} live words`),
			freeWords: integer(fields[8], `GC sample ${index} free words`),
			majorCollections: integer(fields[9], `GC sample ${index} major collections`),
			compactions: integer(fields[10], `GC sample ${index} compactions`),
			topHeapWords: integer(fields[11], `GC sample ${index} top heap words`),
			stackSize: integer(fields[12], `GC sample ${index} stack size`),
		}
		if (row.activeLeases !== 0) fail(`compacted GC sample ${index} still has ${row.activeLeases} active cache leases`)
		if (index > 0 && row.majorCollections <= integer(lines[index - 1].split('\t')[9], `GC sample ${index - 1} major collections`)) {
			fail(`compacted GC sample ${index} did not record a newer major collection`)
		}
		return row
	})
}

function expectedRssEvents() {
	return ['baseline', ...Array.from({length: EXPECTED_REQUESTS}, (_, index) => `request-${index + 1}`)]
}

function parseRssRows(contents) {
	const grouped = new Map()
	const lines = contents.trim().length === 0 ? [] : contents.trim().split('\n')
	for (const [index, line] of lines.entries()) {
		const fields = line.split('\t')
		if (fields.length !== 3) fail(`RSS sample row ${index} has ${fields.length} fields instead of 3`)
		const [event, rawPid, rawRss] = fields
		const pid = integer(rawPid, `RSS sample ${index} PID`, {positive: true})
		const rssKb = integer(rawRss, `RSS sample ${index} KiB`)
		if (!grouped.has(event)) grouped.set(event, new Map())
		const processes = grouped.get(event)
		if (processes.has(pid)) fail(`RSS sample ${event} records PID ${pid} more than once`)
		processes.set(pid, rssKb)
	}

	const expected = expectedRssEvents()
	if (grouped.size !== expected.length) fail(`expected ${expected.length} owned-process RSS samples, found ${grouped.size}`)
	const baselinePids = [...(grouped.get('baseline') ?? new Map()).keys()].sort((left, right) => left - right)
	if (baselinePids.length === 0) fail('baseline RSS sample has no repository-owned server process')
	const totals = new Map()
	for (const event of expected) {
		const processes = grouped.get(event)
		if (processes == null) fail(`missing owned-process RSS sample ${event}`)
		const pids = [...processes.keys()].sort((left, right) => left - right)
		if (pids.join(',') !== baselinePids.join(',')) {
			fail(`owned server process set changed at ${event}: baseline=${baselinePids.join(',')} actual=${pids.join(',')}`)
		}
		totals.set(event, [...processes.values()].reduce((sum, value) => sum + value, 0))
	}
	return {totals, processCount: baselinePids.length}
}

function evaluateMemoryPlateau(gcContents, rssContents, wordBytes) {
	if (!Number.isSafeInteger(wordBytes) || wordBytes <= 0) fail(`word bytes must be a positive integer, got ${wordBytes}`)
	const gcRows = parseGcRows(gcContents)
	const rss = parseRssRows(rssContents)
	const baseline = gcRows[0]
	const after10 = gcRows[10]
	const after20 = gcRows[20]
	const final = gcRows[30]
	const liveOverallGrowthBytes = (final.liveWords - baseline.liveWords) * wordBytes
	const liveFinalWindowGrowthBytes = (final.liveWords - after20.liveWords) * wordBytes
	if (liveOverallGrowthBytes > OVERALL_LIMIT_BYTES) {
		fail(`thirty requests retained ${liveOverallGrowthBytes} bytes of live OCaml heap; limit is ${OVERALL_LIMIT_BYTES}`)
	}
	if (liveFinalWindowGrowthBytes > FINAL_WINDOW_LIMIT_BYTES) {
		fail(`final ten requests retained ${liveFinalWindowGrowthBytes} bytes of live OCaml heap; limit is ${FINAL_WINDOW_LIMIT_BYTES}`)
	}

	const rssBaselineKb = rss.totals.get('baseline')
	const rssAfter10Kb = rss.totals.get('request-10')
	const rssAfter20Kb = rss.totals.get('request-20')
	const rssFinalKb = rss.totals.get('request-30')
	const rssOverallGrowthKb = rssFinalKb - rssBaselineKb
	const rssPriorWindowGrowthKb = rssAfter20Kb - rssAfter10Kb
	const rssFinalWindowGrowthKb = rssFinalKb - rssAfter20Kb
	if (rssOverallGrowthKb > OVERALL_RSS_LIMIT_KB) {
		fail(`owned server RSS grew by ${rssOverallGrowthKb} KiB across thirty requests; limit is ${OVERALL_RSS_LIMIT_KB} KiB`)
	}
	if (rssPriorWindowGrowthKb > FINAL_WINDOW_RSS_OBSERVATION_KB
		&& rssFinalWindowGrowthKb > FINAL_WINDOW_RSS_OBSERVATION_KB) {
		fail(`owned server RSS grew by more than ${FINAL_WINDOW_RSS_OBSERVATION_KB} KiB in two consecutive ten-request windows`)
	}

	return {
		wordBytes,
		processCount: rss.processCount,
		liveBaselineWords: baseline.liveWords,
		liveAfter10Words: after10.liveWords,
		liveAfter20Words: after20.liveWords,
		liveFinalWords: final.liveWords,
		liveOverallGrowthBytes,
		liveFinalWindowGrowthBytes,
		rssBaselineKb,
		rssAfter10Kb,
		rssAfter20Kb,
		rssFinalKb,
		rssOverallGrowthKb,
		rssPriorWindowGrowthKb,
		rssFinalWindowGrowthKb,
		rssFinalWindowStatus: rssFinalWindowGrowthKb > FINAL_WINDOW_RSS_OBSERVATION_KB
			? 'reserved-capacity-observed'
			: 'bounded',
	}
}

function marker(result) {
	return [
		'REFLAXE_OCAML_COMPLETE_PROGRAM_SERVER_MEMORY:PASS',
		`process_count=${result.processCount}`,
		`word_bytes=${result.wordBytes}`,
		`live_baseline_words=${result.liveBaselineWords}`,
		`live_after10_words=${result.liveAfter10Words}`,
		`live_after20_words=${result.liveAfter20Words}`,
		`live_final_words=${result.liveFinalWords}`,
		`live_overall_growth_bytes=${result.liveOverallGrowthBytes}`,
		`live_final_window_growth_bytes=${result.liveFinalWindowGrowthBytes}`,
		`rss_baseline_kb=${result.rssBaselineKb}`,
		`rss_after10_kb=${result.rssAfter10Kb}`,
		`rss_after20_kb=${result.rssAfter20Kb}`,
		`rss_final_kb=${result.rssFinalKb}`,
		`rss_overall_growth_kb=${result.rssOverallGrowthKb}`,
		`rss_prior_window_growth_kb=${result.rssPriorWindowGrowthKb}`,
		`rss_final_window_growth_kb=${result.rssFinalWindowGrowthKb}`,
		`rss_final_window_status=${result.rssFinalWindowStatus}`,
	].join(' ')
}

if (require.main === module) {
	try {
		if (process.argv.length !== 5) fail('usage: reflaxe-ocaml-memory-plateau.js <gc-events.tsv> <rss-events.tsv> <word-bytes>')
		const result = evaluateMemoryPlateau(
			fs.readFileSync(process.argv[2], 'utf8'),
			fs.readFileSync(process.argv[3], 'utf8'),
			integer(process.argv[4], 'word bytes', {positive: true}),
		)
		console.log(marker(result))
	} catch (error) {
		console.error(`reflaxe.ocaml memory plateau proof: ${error?.message ?? error}`)
		process.exit(1)
	}
}

module.exports = {evaluateMemoryPlateau, marker}
