'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')

/**
 * Proves that typed Haxe process operations, rather than a generated-module
 * name scan, explain why the portable package contains HxProcess.
 */
const report = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
const expectedFields = [
	'close',
	'flush_stdin',
	'kill',
	'read_byte',
	'read_line',
	'spawn',
	'write_byte',
	'write_string',
]
const requirements = report.requirements
	.filter((requirement) => requirement.semanticCapability === 'haxe-process')
	.sort((left, right) => left.id.localeCompare(right.id))

assert(report.compilerObservedModulesWithRequirementRoots.includes('HxProcess'), 'HxProcess must overlap an explicit requirement root')
assert(!report.compilerObservedModulesWithoutRequirementRoots.includes('HxProcess'), 'HxProcess must not remain in the unrooted module set')
assert.deepEqual(
	requirements.map((requirement) => requirement.id),
	expectedFields.map((field) => `native:sys.io.Process::sys.io._Process.NativeHxProcess.${field}:runtime:haxe-process`)
)

for (const [index, requirement] of requirements.entries()) {
	const field = expectedFields[index]
	assert.equal(requirement.sourceKind, 'native-boundary')
	assert.equal(requirement.cause, 'native-boundary')
	assert.equal(requirement.implementationFeature, 'haxe-process-v1')
	assert.deepEqual(requirement.rootModules, ['HxProcess'])
	assert.deepEqual(requirement.profileEligibility, ['metal', 'portable'])
	assert.deepEqual(requirement.subject, {
		id: `sys.io.Process::sys.io._Process.NativeHxProcess.${field} -> HxProcess.${field}`,
		kind: 'native-boundary',
	})
}

console.log('TYPED_HAXE_PROCESS_RUNTIME_REQUIREMENT:PASS')
