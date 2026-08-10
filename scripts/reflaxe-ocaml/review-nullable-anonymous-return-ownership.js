#!/usr/bin/env node
'use strict'

/**
 * Independently checks who owns nullable anonymous-object return decisions.
 *
 * The compiler and public Haxe inspector already validate each report while it
 * is produced. This small Node.js reader is deliberately separate: it compares
 * retained reports and rejects a return signal that borrows another function's
 * anonymous shape, representation, callable boundary, or boxing policy.
 *
 * With no arguments it reviews every currently generated portable report. File
 * arguments may be supplied to review a smaller, explicitly retained evidence
 * set. Missing output directories are ignored only during automatic discovery.
 */

const fs = require('fs')
const path = require('path')

const ROOT = path.resolve(__dirname, '..', '..')
const FIXTURE_ROOT = path.join(ROOT, 'test', 'portable', 'fixtures')
const SHA256 = /^sha256:[0-9a-f]{64}$/
const RESULT_SOURCE = 'static-nullable-anonymous-declaration'
const RESULT_PROOF = 'static-nullable-anonymous-function-result-v1'
const CONTROL_PROOF = 'exact-anonymous-carrier-early-return-control-v1'
const CONTROL_CONVERSION = 'preserve-anonymous-carrier'

function fail(message) {
	throw new Error(message)
}

function discoveredReports() {
	return fs.readdirSync(FIXTURE_ROOT, {withFileTypes: true})
		.filter(entry => entry.isDirectory())
		.map(entry => path.join(FIXTURE_ROOT, entry.name, 'out', 'ocaml_lowering_report.json'))
		.filter(file => fs.existsSync(file))
		.sort()
}

function requireEqual(actual, expected, owner, field) {
	if (actual !== expected)
		fail(`${owner} has ${field}=${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`)
}

const reportPaths = process.argv.length > 2
	? process.argv.slice(2).map(file => path.resolve(file))
	: discoveredReports()
if (reportPaths.length === 0)
	fail('no generated OCaml lowering reports were supplied or discovered')

const identityByFunction = new Map()
const productionOwners = new Set()
let boundaryCount = 0
let controlCount = 0

for (const reportPath of reportPaths) {
	const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
	if (report.schemaVersion !== 72)
		fail(`${reportPath} uses lowering schema ${report.schemaVersion}; expected 72`)
	const boundaries = (report.functionResultBoundaries ?? []).filter(item => item.source === RESULT_SOURCE)
	const boundaryByFunction = new Map()
	for (const boundary of boundaries) {
		const owner = `${reportPath}: function result ${boundary.functionId}`
		if (boundaryByFunction.has(boundary.functionId))
			fail(`${owner} appears more than once`)
		boundaryByFunction.set(boundary.functionId, boundary)

		const proof = boundary.anonymousStructure
		const result = boundary.result
		const structure = (report.anonymousStructures ?? []).find(item => item.id === proof?.structureId)
		const representation = (report.representations ?? []).find(item => item.id === proof?.representationId)
		if (!proof || !result || !structure || !representation)
			fail(`${owner} does not resolve its result, anonymous structure, and representation owners`)
		requireEqual(boundary.callableBoundaryId, null, owner, 'callableBoundaryId')
		requireEqual(boundary.proofId, RESULT_PROOF, owner, 'proofId')
		requireEqual(result.conversion, 'identity', owner, 'result.conversion')
		requireEqual(result.inputSemanticTypeId, proof.semanticTypeId, owner, 'result.inputSemanticTypeId')
		requireEqual(result.outputSemanticTypeId, proof.semanticTypeId, owner, 'result.outputSemanticTypeId')
		requireEqual(result.inputCarrierTypeId, 'Obj.t', owner, 'result.inputCarrierTypeId')
		requireEqual(result.outputCarrierTypeId, 'Obj.t', owner, 'result.outputCarrierTypeId')
		requireEqual(result.inputRepresentationId, proof.representationId, owner, 'result.inputRepresentationId')
		requireEqual(result.outputRepresentationId, proof.representationId, owner, 'result.outputRepresentationId')
		requireEqual(structure.semanticTypeId, proof.semanticTypeId, owner, 'structure.semanticTypeId')
		requireEqual(structure.revision, proof.structureRevision, owner, 'structure.revision')
		requireEqual(structure.representationId, proof.representationId, owner, 'structure.representationId')
		requireEqual(structure.representationRevision, proof.representationRevision, owner, 'structure.representationRevision')
		requireEqual(representation.semanticTypeId, proof.semanticTypeId, owner, 'representation.semanticTypeId')
		requireEqual(representation.carrierTypeId, 'Obj.t', owner, 'representation.carrierTypeId')
		requireEqual(representation.boxingPolicy, 'direct-runtime-container', owner, 'representation.boxingPolicy')
		requireEqual(representation.revision, proof.representationRevision, owner, 'representation.revision')
		if (!SHA256.test(proof.structureRevision) || !SHA256.test(proof.representationRevision))
			fail(`${owner} has a malformed structure or representation revision`)
		if ((report.callableBoundaries ?? []).some(item => item.functionId === boundary.functionId))
			fail(`${owner} also appears in the callable ABI inventory`)

		const returnControls = (report.controls ?? []).filter(item => item.functionId === boundary.functionId && item.kind === 'return')
		const admission = (report.controlAdmissions ?? []).find(item => item.functionId === boundary.functionId)
		const returnFamily = admission?.families?.find(item => item.family === 'return')
		if (returnFamily?.status !== 'admitted'
			|| returnFamily.occurrenceCount !== returnControls.length
			|| returnFamily.decisionCount !== returnControls.length
			|| returnControls.length === 0) {
			fail(`${owner} does not have one admitted decision for every nested return occurrence`)
		}
		for (const control of returnControls) {
			const payload = control.payload
			const controlOwner = `${reportPath}: control ${control.id}`
			if (!payload)
				fail(`${controlOwner} has no payload`)
			requireEqual(control.proofId, CONTROL_PROOF, controlOwner, 'proofId')
			requireEqual(payload.proofId, CONTROL_PROOF, controlOwner, 'payload.proofId')
			requireEqual(payload.conversion, CONTROL_CONVERSION, controlOwner, 'payload.conversion')
			requireEqual(payload.inputSemanticTypeId, proof.semanticTypeId, controlOwner, 'payload.inputSemanticTypeId')
			requireEqual(payload.outputSemanticTypeId, proof.semanticTypeId, controlOwner, 'payload.outputSemanticTypeId')
			requireEqual(payload.inputCarrierTypeId, 'Obj.t', controlOwner, 'payload.inputCarrierTypeId')
			requireEqual(payload.outputCarrierTypeId, 'Obj.t', controlOwner, 'payload.outputCarrierTypeId')
			requireEqual(payload.inputRepresentationId, proof.representationId, controlOwner, 'payload.inputRepresentationId')
			requireEqual(payload.outputRepresentationId, proof.representationId, controlOwner, 'payload.outputRepresentationId')
			requireEqual(payload.representationRevision, proof.representationRevision, controlOwner, 'payload.representationRevision')
		}

		const stableIdentity = JSON.stringify({
			id: boundary.id,
			semanticTypeId: proof.semanticTypeId,
			structureId: proof.structureId,
			representationId: proof.representationId,
			representationRevision: proof.representationRevision
		})
		// The structure revision deliberately includes the current program binding,
		// so it must be exact inside one report but may differ across applications.
		// Logical shape and representation identities must remain stable.
		const priorIdentity = identityByFunction.get(boundary.functionId)
		if (priorIdentity !== undefined && priorIdentity !== stableIdentity)
			fail(`${owner} changes stable anonymous ownership across retained reports`)
		identityByFunction.set(boundary.functionId, stableIdentity)
		if (boundary.functionId.startsWith('haxe.CallStack|') || boundary.functionId.startsWith('haxe.NativeStackTrace|'))
			productionOwners.add(boundary.functionId.split('|')[0])
		boundaryCount++
		controlCount += returnControls.length
	}

	for (const control of report.controls ?? []) {
		if (control.kind === 'return'
			&& control.payload?.conversion === CONTROL_CONVERSION
			&& !boundaryByFunction.has(control.functionId)) {
			fail(`${reportPath}: control ${control.id} preserves an anonymous carrier without a result owner`)
		}
	}
}

for (const requiredOwner of ['haxe.CallStack', 'haxe.NativeStackTrace']) {
	if (!productionOwners.has(requiredOwner))
		fail(`retained reports do not contain the production owner ${requiredOwner}`)
}

console.log(`NULLABLE_ANONYMOUS_RETURN_OWNERSHIP_REVIEW:PASS reports=${reportPaths.length} functions=${identityByFunction.size} boundaries=${boundaryCount} returns=${controlCount}`)
