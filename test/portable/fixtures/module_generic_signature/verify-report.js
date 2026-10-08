#!/usr/bin/env node

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const fixture = __dirname
const root = path.resolve(fixture, '../../../..')
const output = path.join(fixture, 'out')
const lowering = JSON.parse(fs.readFileSync(path.join(output, 'ocaml_lowering_report.json'), 'utf8'))
const generic = report => report.calls.filter(call => call.kind === 'generic-instance-haxe-method')
assert.equal(lowering.schemaVersion, 94)
assert.equal(lowering.callModel, 'typed-ocaml-directional-call-boundary-v34')
assert.equal(generic(lowering).length, 14)
assert(generic(lowering).some(call => call.genericInstanceTarget.result.kind === 'unbox-bool'))
assert(generic(lowering).some(call => call.genericInstanceTarget.resultShape.kind === 'array'))
for (const kind of ['nullable-int', 'nullable-bool']) {
	const call = generic(lowering).find(entry => entry.genericInstanceTarget.resultShape.kind === kind)
	assert(call, `missing ${kind} generic boundary`)
	assert.equal(call.genericInstanceTarget.result.kind, kind === 'nullable-bool' ? 'unbox-nullable-bool' : 'identity')
}

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-generic-report-'))
const cases = []
try {
	/** Each copied output changes one fact so diagnostics identify the broken contract. */
	function corrupt(label, pattern, mutate) {
		const destination = path.join(temporary, String(cases.length))
		fs.cpSync(output, destination, { recursive: true, filter: source => path.basename(source) !== '_build' })
		const report = structuredClone(lowering)
		mutate(report, generic(report)[0])
		fs.writeFileSync(path.join(destination, 'ocaml_lowering_report.json'), JSON.stringify(report))
		cases.push({ label, pattern, destination })
	}
	corrupt('missing generic target', /Generic call report/, (_, call) => { call.genericInstanceTarget = null })
	corrupt('unknown target field', /Generic call report/, (_, call) => { call.genericInstanceTarget.unchecked = true })
	corrupt('unknown conversion', /Generic call report/, (_, call) => { call.genericInstanceTarget.result.kind = 'unchecked-cast' })
	corrupt('wrong result conversion', /generic|conversion/i, (_, call) => {
		const kind = call.genericInstanceTarget.result.kind === 'identity' ? 'box-value' : 'identity'
		call.genericInstanceTarget.result = { kind, parameter: null, children: [] }
	})
	corrupt('foreign receiver proof', /matching direct-record receiver proof/, (_, call) => {
		call.genericInstanceTarget.receiverRepresentationId = 'foreign-receiver'
	})
	corrupt('stale caller body', /stale|revision|caller/i, (_, call) => { call.bodyRevision = 'body:stale' })
	corrupt('reordered source effects', /schedule|evaluation|order|invalid receiver materialization/i, (_, call) => { call.evaluationSchedule.reverse() })
	corrupt('missing Boolean runtime requirement', /missing Boolean carrier requirement/, report => {
		const call = generic(report).find(entry => entry.genericInstanceTarget.result.kind === 'unbox-bool')
		const index = report.runtimeRequirements.findIndex(entry => entry.decisionId === call.id)
		assert(index >= 0)
		report.runtimeRequirements.splice(index, 1)
		report.runtimeRequirementCount = report.runtimeRequirements.length
	})
	const inspected = spawnSync(process.env.HAXE_BIN || 'haxe', [
		'-cp', 'packages/reflaxe.ocaml/src', '-cp', fixture,
		'--macro', 'nullSafety("reflaxe.ocaml")', '--run', 'InspectReports',
		fixture, output, ...cases.map(entry => entry.destination)
	], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], maxBuffer: 50 * 1024 * 1024, timeout: 600000 })
	if (inspected.error) {
		process.stderr.write(inspected.stderr || '')
		throw inspected.error
	}
	assert.equal(inspected.status, 0, inspected.stdout + (inspected.stderr || ''))
	const reports = JSON.parse(inspected.stdout)
	assert.equal(reports.length, cases.length + 1)
	assert.equal(reports[0].summary.valid, true, JSON.stringify(reports[0]))
	assert.deepEqual(generic(reports[0].lowering).map(call => call.genericInstanceTarget),
		generic(lowering).map(call => call.genericInstanceTarget), 'inspection must preserve all conversion details')
	for (const [index, entry] of cases.entries()) {
		assert.equal(reports[index + 1].summary.valid, false, `accepted ${entry.label}`)
		assert.equal(reports[index + 1].lowering.status, 'invalid', entry.label)
		assert.match(reports[index + 1].lowering.message, entry.pattern, entry.label)
	}
} finally {
	fs.rmSync(temporary, { recursive: true, force: true })
}
console.log('GENERIC_CALL_PUBLIC_REPORT_AND_CORRUPTION:PASS')
