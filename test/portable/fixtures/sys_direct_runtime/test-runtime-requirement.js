'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')

/**
 * Proves that each direct typed Sys declaration selects its exact HxSys
 * function and that no declaration is inferred merely from seeing HxSys in
 * generated OCaml.
 */
const report = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
const expectedBoundaries = [
	['args', 'args'],
	['cpuTime', 'cpuTime'],
	['executablePath', 'programPath'],
	['exit', 'exit'],
	['getChar', 'getChar'],
	['getCwd', 'getCwd'],
	['getEnv', 'getEnv'],
	['environment', 'environment'],
	['programPath', 'programPath'],
	['setCwd', 'setCwd'],
	['sleep', 'sleep'],
	['systemName', 'systemName'],
	['time', 'time'],
]
const requirements = report.requirements
	.filter((requirement) => requirement.semanticCapability === 'haxe-system')
	.sort((left, right) => left.id.localeCompare(right.id))
const requirementsById = new Map(requirements.map((requirement) => [requirement.id, requirement]))

assert(report.compilerObservedModulesWithRequirementRoots.includes('HxSys'), 'HxSys must overlap an explicit requirement root')
assert(!report.compilerObservedModulesWithoutRequirementRoots.includes('HxSys'), 'HxSys must not remain in the unrooted module set')
assert.equal(requirementsById.size, expectedBoundaries.length)

for (const [sourceField, nativeField] of expectedBoundaries) {
	const boundary = `Sys::Sys.${sourceField}`
	const id = `native:${boundary}:runtime:haxe-system`
	const requirement = requirementsById.get(id)
	assert(requirement, `Missing typed Haxe system runtime requirement ${id}`)
	assert.equal(requirement.sourceKind, 'native-boundary')
	assert.equal(requirement.cause, 'native-boundary')
	assert.equal(requirement.implementationFeature, 'haxe-system-v1')
	assert.deepEqual(requirement.rootModules, ['HxSys'])
	assert.deepEqual(requirement.profileEligibility, ['metal', 'portable'])
	assert.deepEqual(requirement.subject, {
		id: `${boundary} -> HxSys.${nativeField}`,
		kind: 'native-boundary',
	})
}

console.log('TYPED_HAXE_SYSTEM_RUNTIME_REQUIREMENTS:PASS')
