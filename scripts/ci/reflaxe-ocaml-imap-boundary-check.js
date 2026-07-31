#!/usr/bin/env node

/**
 * Keeps generic standard-Map semantics in the typed call plan.
 *
 * The OCaml builder may render a sealed carrier and runtime operation. It must
 * not identify haxe.Constraints.IMap, infer its key kind, or rediscover the
 * source method after typing has finished.
 */

const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const builderPath = path.join(
	repoRoot,
	'packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx'
)
const callPlanPath = path.join(
	repoRoot,
	'packages/reflaxe.ocaml/src/reflaxe/ocaml/lowered/OcamlCallPlan.hx'
)
const targetModelPath = path.join(
	repoRoot,
	'packages/reflaxe.ocaml/src/reflaxe/ocaml/lowered/OcamlStandardIMapCallModel.hx'
)

const builder = fs.readFileSync(builderPath, 'utf8')
const callPlan = fs.readFileSync(callPlanPath, 'utf8')
const targetModel = fs.readFileSync(targetModelPath, 'utf8')
const failures = []

for (const forbidden of [
	'haxe.Constraints.IMap',
	'isHaxeConstraintsIMapClass',
	'mapKeyKindFromType',
	'mapKeyKindFromIMapExpr',
]) {
	if (builder.includes(forbidden))
		failures.push(`OcamlBuilder still contains forbidden generic IMap inference marker: ${forbidden}`)
}

for (const required of [
	'buildPlannedStandardIMapCall',
	'OcamlStandardIMapCallContract.require(target)',
	'target.runtimeFunction',
	'target.resultForm',
]) {
	if (!builder.includes(required))
		failures.push(`OcamlBuilder no longer consumes required sealed IMap fact: ${required}`)
}

for (const required of [
	'OcamlCallKind.StandardIMapMethod',
	'OcamlStandardIMapCallContract.select',
	'OcamlStandardIMapCallContract.matches',
	'standardIMapTarget',
]) {
	if (!callPlan.includes(required))
		failures.push(`typed call planning no longer owns required IMap seam: ${required}`)
}

for (const required of [
	'class OcamlStandardIMapCallContract',
	'fixed String, Int, or non-generic class key',
	'Enum maps, type-parameter keys, structural keys',
	'public static function require',
]) {
	if (!targetModel.includes(required))
		failures.push(`standard IMap target model lost required closed-slice contract: ${required}`)
}

if (failures.length > 0) {
	console.error('Standard IMap typed-target boundary failed.')
	for (const failure of failures)
		console.error(`- ${failure}`)
	process.exit(1)
}

console.log('REFLAXE_OCAML_IMAP_BOUNDARY:PASS')
