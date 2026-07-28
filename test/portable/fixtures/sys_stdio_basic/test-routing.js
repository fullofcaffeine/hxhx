'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')

/**
 * Proves that Sys routes through the generated Haxe Stdio module while only
 * NativeHxStdio selects the checked OCaml HxStdio runtime source.
 */
const generatedMain = fs.readFileSync('out/Main.ml', 'utf8')
const report = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
const expectedCalls = new Map([
	['stdin', 1],
	['stdout', 2],
	['stderr', 2],
])

for (const [field, expectedCount] of expectedCalls) {
	const matches = generatedMain.match(new RegExp(`Sys_io_Stdio\\.${field} \\(\\)`, 'g')) ?? []
	assert.equal(matches.length, expectedCount, `Expected ${expectedCount} generated Sys_io_Stdio.${field} calls`)
}

assert(!generatedMain.includes('HxStdio.'), 'Main must not bypass the generated Haxe Stdio module')

const requirements = report.requirements.filter((requirement) => requirement.semanticCapability === 'haxe-standard-io')
assert.equal(requirements.length, 5)
assert(report.compilerObservedModulesWithRequirementRoots.includes('HxStdio'), 'HxStdio must overlap an explicit requirement root')
assert(!report.compilerObservedModulesWithoutRequirementRoots.includes('HxStdio'), 'HxStdio must not remain in the unrooted module set')

for (const requirement of requirements) {
	assert.equal(requirement.sourceKind, 'native-boundary')
	assert.equal(requirement.cause, 'native-boundary')
	assert.equal(requirement.implementationFeature, 'haxe-standard-io-v1')
	assert.deepEqual(requirement.rootModules, ['HxStdio'])
	assert(requirement.id.startsWith('native:sys.io.Stdio::sys.io._Stdio.NativeHxStdio.'))
	assert(requirement.subject.id.includes(' -> HxStdio.'))
	assert(!requirement.id.includes('native:Sys::'), 'Sys stream declarations must not pretend generated Haxe modules are runtime roots')
}

console.log('TYPED_HAXE_STDIO_ROUTING:PASS')
