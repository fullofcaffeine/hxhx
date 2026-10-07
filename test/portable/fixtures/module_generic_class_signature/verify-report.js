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
assert.equal(lowering.schemaVersion, 92)
assert.equal(lowering.callModel, 'typed-ocaml-directional-call-boundary-v33')
assert.equal(generic(lowering).length, 8)
assert(generic(lowering).some(call => call.genericInstanceTarget.resultShape.kind === 'nullable-class'))

/** Changes only class proof fields inside one otherwise coherent conversion target. */
function visitClass(value, change) {
	if (!value || typeof value !== 'object') return
	if (value.kind === 'class' || value.kind === 'nullable-class') change(value)
	for (const child of Object.values(value)) visitClass(child, change)
}

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-generic-class-'))
const cases = []
try {
	function corrupt(label, pattern, change) {
		const destination = path.join(temporary, String(cases.length))
		fs.cpSync(output, destination, { recursive: true, filter: source => path.basename(source) !== '_build' })
		const report = structuredClone(lowering)
		const call = generic(report).find(entry => entry.genericInstanceTarget.resultShape.classTypeId === 'model.Payload')
		assert(call, 'missing Payload call to corrupt')
		change(call.genericInstanceTarget, report)
		fs.writeFileSync(path.join(destination, 'ocaml_lowering_report.json'), JSON.stringify(report))
		cases.push({ label, pattern, destination })
	}
	corrupt('foreign class proof', /matching class-value representation proof/, target => {
		visitClass(target, value => { value.classRepresentationId = 'representation:foreign' })
	})
	corrupt('different registered class', /matching class-value representation proof/, (target, report) => {
		const other = report.representations.find(value =>
			value.semanticTypeId === 'model.OtherPayload' && value.domain === 'generic-call-value')
		assert(other)
		visitClass(target, value => { value.classRepresentationId = other.id })
	})
	corrupt('missing class identity', /Generic call report/, target => {
		visitClass(target, value => { delete value.classTypeId })
	})
	corrupt('previous report schema', /Unsupported lowering report schema 90; expected 91/, (_, report) => {
		report.schemaVersion = 91
	})
	const inspected = spawnSync(process.env.HAXE_BIN || 'haxe', [
		'-cp', 'packages/reflaxe.ocaml/src', '-cp', path.join(fixture, '../module_generic_signature'),
		'--macro', 'nullSafety("reflaxe.ocaml")', '--run', 'InspectReports',
		fixture, output, ...cases.map(entry => entry.destination)
	], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], timeout: 600000, maxBuffer: 50 * 1024 * 1024 })
	if (inspected.error) throw inspected.error
	assert.equal(inspected.status, 0, inspected.stdout)
	const reports = JSON.parse(inspected.stdout)
	assert.equal(reports.length, cases.length + 1)
	assert.equal(reports[0].summary.valid, true, JSON.stringify(reports[0]))
	for (const [index, entry] of cases.entries()) {
		assert.equal(reports[index + 1].summary.valid, false, entry.label)
		assert.equal(reports[index + 1].lowering.status, 'invalid', entry.label)
		assert.match(reports[index + 1].lowering.message, entry.pattern, entry.label)
	}
} finally {
	fs.rmSync(temporary, { recursive: true, force: true })
}
console.log('GENERIC_CLASS_PUBLIC_PROOFS:PASS')
