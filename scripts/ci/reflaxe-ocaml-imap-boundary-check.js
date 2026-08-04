#!/usr/bin/env node

/**
 * Protects the point where a typed Haxe IMap call becomes OCaml syntax.
 *
 * The compiler first records which IMap method is called and which concrete
 * value is being converted to the shared interface carrier. That saved choice
 * is called a sealed decision: later code may validate and render it, but may
 * not guess the receiver or key family again from a type name. This check keeps
 * the planner, request-local lookup, and syntax helper on that one path.
 */

const fs = require('fs')
const path = require('path')

function requireMarkers(failures, owner, source, markers) {
	for (const marker of markers) {
		if (!source.includes(marker))
			failures.push(`${owner} no longer contains the required typed IMap boundary: ${marker}`)
	}
}

function rejectMarkers(failures, owner, source, markers) {
	for (const marker of markers) {
		if (source.includes(marker))
			failures.push(`${owner} contains a forbidden syntax-time IMap inference marker: ${marker}`)
	}
}

/**
 * Returns every ownership violation found in already-loaded source text.
 *
 * Accepting strings makes the guard independently testable: its fixture can
 * remove one required handoff or reintroduce one forbidden inference helper
 * without editing the repository being checked.
 */
function checkIMapBoundary({builder, interfacePlan, interfaceSyntax, targetModel}) {
	const failures = []

	rejectMarkers(failures, 'OcamlBuilder', builder, [
		'buildPlannedStandardIMapCall',
		'mapKeyKindFromType',
		'mapKeyKindFromIMapExpr',
	])
	requireMarkers(failures, 'OcamlBuilder', builder, [
		'currentIMapInterfacePlan.callFor(e)',
		'buildPlannedIMapInterfaceCall',
		'OcamlIMapInterfaceSyntax.buildCall(decision, callee, arguments, iMapInterfaceSyntaxServices())',
		'an exact IMap interface call reached syntax without its sealed dispatch decision',
		'currentIMapInterfacePlan.requireConversion(rhs, lhsType)',
		'buildPlannedIMapInterfaceConversion',
		'a concrete value reached an IMap boundary without an active interface-conversion plan',
	])

	requireMarkers(failures, 'OcamlIMapInterfacePlan', interfacePlan, [
		'class OcamlIMapInterfacePlanner',
		'function selectCall(',
		'function selectConversion(',
		'OcamlIMapInterfaceContract.requireCall(decision)',
		'OcamlIMapInterfaceContract.requireConversion(decision)',
		'OcamlStandardMapCarrierContract.kindForClass(classType)',
	])

	rejectMarkers(failures, 'OcamlIMapInterfaceSyntax', interfaceSyntax, [
		'mapKeyKindFromType',
		'mapKeyKindFromIMapExpr',
		'OcamlStandardMapCarrierContract.kindForClass',
	])
	requireMarkers(failures, 'OcamlIMapInterfaceSyntax', interfaceSyntax, [
		'OcamlIMapInterfacePlan.requireCallDecision(decision)',
		'OcamlIMapInterfacePlan.requireConversionDecision(materialization.decision)',
		'final keyKind = materialization.decision.standardKeyKind',
		'final operation = OcamlStandardIMapCallContract.operationFor(fieldRef.get().name, arguments.length)',
	])

	requireMarkers(failures, 'OcamlIMapInterfaceContract', targetModel, [
		'class OcamlIMapInterfaceContract',
		'public static function requireConversion',
		'public static function requireCall',
		'public static function runtimeRequirementIds',
	])

	return failures
}

function loadRepositorySources(repoRoot) {
	const sourceRoot = path.join(repoRoot, 'packages/reflaxe.ocaml/src/reflaxe/ocaml')
	return {
		builder: fs.readFileSync(path.join(sourceRoot, 'ast/OcamlBuilder.hx'), 'utf8'),
		interfacePlan: fs.readFileSync(path.join(sourceRoot, 'lowered/OcamlIMapInterfacePlan.hx'), 'utf8'),
		interfaceSyntax: fs.readFileSync(path.join(sourceRoot, 'ast/OcamlIMapInterfaceSyntax.hx'), 'utf8'),
		targetModel: fs.readFileSync(path.join(sourceRoot, 'lowered/OcamlIMapInterfaceModel.hx'), 'utf8'),
	}
}

function main() {
	const repoRoot = path.resolve(__dirname, '../..')
	const failures = checkIMapBoundary(loadRepositorySources(repoRoot))
	if (failures.length > 0) {
		console.error('The typed IMap ownership boundary is incomplete.')
		for (const failure of failures) console.error(`- ${failure}`)
		process.exit(1)
	}
	console.log('REFLAXE_OCAML_IMAP_BOUNDARY:PASS owner=typed-interface-plan consumer=focused-interface-syntax')
}

if (require.main === module) main()

module.exports = {checkIMapBoundary, loadRepositorySources}
