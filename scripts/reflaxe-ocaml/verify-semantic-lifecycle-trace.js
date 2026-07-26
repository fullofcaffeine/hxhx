#!/usr/bin/env node
'use strict'

const crypto = require('node:crypto')
const fs = require('node:fs')

const [tracePath, expectedFunction] = process.argv.slice(2)
if (!tracePath || !expectedFunction) {
	console.error('Usage: verify-semantic-lifecycle-trace.js <trace.json> <function-id-substring>')
	process.exit(2)
}

const report = JSON.parse(fs.readFileSync(tracePath, 'utf8'))

function fail(message) {
	console.error(`Semantic lifecycle trace check failed: ${message}`)
	process.exit(1)
}

function eventsFor(preprocessorSuffix, phase) {
	return report.events.filter(event => event.preprocessorId.endsWith(preprocessorSuffix) && event.phase === phase)
}

function oneEvent(preprocessorSuffix, phase) {
	const matches = eventsFor(preprocessorSuffix, phase)
	if (matches.length !== 1) {
		fail(`expected one ${phase} event for ${preprocessorSuffix}, found ${matches.length}`)
	}
	return matches[0]
}

if (report.schemaVersion !== 1 || report.model !== 'reflaxe-ocaml-semantic-lifecycle') {
	fail('unexpected report schema or model')
}
if (report.pipelineRevision !== 'ocaml-function-plans-v17') {
	fail(`unexpected pipeline revision ${report.pipelineRevision}`)
}
if (report.functionFilter !== expectedFunction) {
	fail(`report filter ${report.functionFilter} does not match ${expectedFunction}`)
}
if (!Array.isArray(report.events) || report.events.length === 0 || report.activeEventCount !== report.events.length) {
	fail('active event inventory is empty or inconsistent')
}
if (report.events.some(event => !event.functionId.includes(expectedFunction))) {
	fail('trace contains an unrelated function')
}

const preserveAfter = oneEvent(':reflaxe.ocaml.preserve-place-assignments', 'after')
const cleanupBefore = oneEvent(':remove-pure-expressions', 'before')
const cleanupAfter = oneEvent(':remove-pure-expressions', 'after')
const finalizeBefore = oneEvent(':reflaxe.ocaml.finalize-place-assignments', 'before')
const finalizeAfter = oneEvent(':reflaxe.ocaml.finalize-place-assignments', 'after')
const finalEvent = oneEvent('final', 'final')

if (preserveAfter.artifactIds.length !== 1 || !preserveAfter.artifactIds[0].endsWith(':early-protection')) {
	fail('early protection was not created exactly once')
}
if (JSON.stringify(cleanupBefore.artifactIds) !== JSON.stringify(cleanupAfter.artifactIds)) {
	fail('pure-expression cleanup changed or removed early protection')
}
if (JSON.stringify(finalizeBefore.artifactIds) !== JSON.stringify(cleanupAfter.artifactIds)) {
	fail('final planning did not receive the protected operation from cleanup')
}
if (finalizeAfter.artifactIds.length !== 1 || finalizeAfter.artifactIds[0].endsWith(':early-protection')) {
	fail('final planning did not replace protection with a sealed-plan fingerprint')
}
if (JSON.stringify(finalizeAfter.artifactIds) !== JSON.stringify(finalEvent.artifactIds)) {
	fail('the sealed plan changed before target source construction')
}

const canonical = JSON.stringify(report.events)
const expectedRevision = `sha256:${crypto.createHash('sha256').update(canonical).digest('hex')}`
if (report.traceRevision !== expectedRevision) {
	fail(`trace digest mismatch: ${report.traceRevision} != ${expectedRevision}`)
}

console.log('REFLAXE_OCAML_SEMANTIC_LIFECYCLE_TRACE:PASS')
