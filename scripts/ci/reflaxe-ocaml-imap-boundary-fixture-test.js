#!/usr/bin/env node

/**
 * Proves that the IMap ownership guard notices meaningful architecture drift.
 *
 * These mutations model the mistakes the guard is meant to stop: skipping the
 * saved occurrence lookup, weakening plain-data validation, or choosing a Map
 * carrier again while OCaml syntax is being built. Expected failures are
 * written here by hand; they are not produced by the code under test.
 */

const assert = require('assert')
const path = require('path')
const {checkIMapBoundary, loadRepositorySources} = require('./reflaxe-ocaml-imap-boundary-check.js')

const sources = loadRepositorySources(path.resolve(__dirname, '../..'))
assert.deepStrictEqual(checkIMapBoundary(sources), [], 'the committed typed IMap boundary should satisfy its guard')

function expectMutation(label, field, before, after, expectedFailure) {
	assert(sources[field].includes(before), `${label}: fixture mutation marker is stale: ${before}`)
	const mutated = {...sources, [field]: sources[field].replace(before, after)}
	const failures = checkIMapBoundary(mutated)
	assert(
		failures.some(failure => failure.includes(expectedFailure)),
		`${label}: guard did not report ${expectedFailure}; failures were ${JSON.stringify(failures)}`
	)
}

expectMutation(
	'missing request-local call lookup',
	'builder',
	'currentIMapInterfacePlan.callFor(e)',
	'null',
	'currentIMapInterfacePlan.callFor(e)'
)
expectMutation(
	'missing fail-closed call diagnostic',
	'builder',
	'an exact IMap interface call reached syntax without its sealed dispatch decision',
	'an IMap call used an inferred fallback',
	'an exact IMap interface call reached syntax without its sealed dispatch decision'
)
expectMutation(
	'bypassed call-decision validation',
	'interfaceSyntax',
	'OcamlIMapInterfacePlan.requireCallDecision(decision)',
	'// validation removed by mutation fixture',
	'OcamlIMapInterfacePlan.requireCallDecision(decision)'
)
expectMutation(
	'syntax-time carrier selection',
	'interfaceSyntax',
	'class OcamlIMapInterfaceSyntax {',
	'class OcamlIMapInterfaceSyntax {\n\tstatic final forbidden = OcamlStandardMapCarrierContract.kindForClass;',
	'OcamlStandardMapCarrierContract.kindForClass'
)
expectMutation(
	'missing pure conversion validation',
	'interfacePlan',
	'OcamlIMapInterfaceContract.requireConversion(decision)',
	'// validation removed by mutation fixture',
	'OcamlIMapInterfaceContract.requireConversion(decision)'
)

console.log('REFLAXE_OCAML_IMAP_BOUNDARY_FIXTURES:PASS mutations=5')
