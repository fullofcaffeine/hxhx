'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

/**
 * Proves that each direct typed Sys declaration selects its exact HxSys
 * function and that no declaration is inferred merely from seeing HxSys in
 * generated OCaml.
 */
const report = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
const expectedBoundaries = [
	['Sys::Sys.args', 'args'],
	['Sys::Sys.cpuTime', 'cpuTime'],
	['Sys::Sys.environment', 'environment'],
	['Sys::Sys.executablePath', 'programPath'],
	['Sys::Sys.exit', 'exit'],
	['Sys::Sys.getChar', 'getChar'],
	['Sys::Sys.getCwd', 'getCwd'],
	['Sys::Sys.getEnv', 'getEnv'],
	['Sys::Sys.programPath', 'programPath'],
	['Sys::Sys.setCwd', 'setCwd'],
	['Sys::Sys.sleep', 'sleep'],
	['Sys::Sys.systemName', 'systemName'],
	['Sys::Sys.time', 'time'],
	['Sys::_Sys.NativeHxSys.commandArgs', 'commandArgs'],
	['Sys::_Sys.NativeHxSys.commandShell', 'commandShell'],
	['Sys::_Sys.NativeHxSys.putEnvValue', 'putEnvValue'],
	['Sys::_Sys.NativeHxSys.removeEnv', 'removeEnv'],
]
const requirements = report.requirements
	.filter((requirement) => requirement.semanticCapability === 'haxe-system')
	.sort((left, right) => left.id.localeCompare(right.id))
const requirementsById = new Map(requirements.map((requirement) => [requirement.id, requirement]))

assert(report.compilerObservedModulesWithRequirementRoots.includes('HxSys'), 'HxSys must overlap an explicit requirement root')
assert(!report.compilerObservedModulesWithoutRequirementRoots.includes('HxSys'), 'HxSys must not remain in the unrooted module set')
assert.equal(requirementsById.size, expectedBoundaries.length)

for (const [boundary, nativeField] of expectedBoundaries) {
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

const generatedMain = fs.readFileSync('out/Main.ml', 'utf8')
for (const nativeField of ['putEnvValue', 'removeEnv', 'commandShell', 'commandArgs'])
	assert(generatedMain.includes(`HxSys.${nativeField}`), `Generated Haxe facade must call HxSys.${nativeField}`)
assert(!generatedMain.includes('HxSys.putEnv '), 'Generated code must not use the removed nullable-option putEnv ABI')
assert(!generatedMain.includes('HxSys.command '), 'Generated code must not use the removed optional command ABI')
assert(!generatedMain.includes('setTimeLocale'), 'Unsupported locale selection must fold to false in Haxe')

const repositoryRoot = path.resolve(__dirname, '../../../..')
const builderSource = fs.readFileSync(path.join(repositoryRoot, 'packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx'), 'utf8')
const sysSource = fs.readFileSync(path.join(repositoryRoot, 'packages/reflaxe.ocaml/std/ocaml/_std/Sys.hx'), 'utf8')
const hxSysSource = fs.readFileSync(path.join(repositoryRoot, 'packages/reflaxe.ocaml/std/runtime/HxSys.ml'), 'utf8')
const stage3EmitterSource = fs.readFileSync(path.join(repositoryRoot, 'packages/hxhx-core/src/EmitterStage.hx'), 'utf8')
const sysBranchStart = builderSource.indexOf('final isBuilderOwnedSysCall')
const sysBranchEnd = builderSource.indexOf('} else if (cls.pack', sysBranchStart)
assert(sysBranchStart >= 0 && sysBranchEnd > sysBranchStart, 'Could not locate the bounded builder-owned Sys branch')
const sysBranch = builderSource.slice(sysBranchStart, sysBranchEnd)
assert(sysBranch.includes('case "print", "println"'), 'Dynamic output must remain the only explicit builder-owned Sys family')
for (const removedField of ['putEnv', 'command', 'setTimeLocale'])
	assert(!sysBranch.includes(`"${removedField}"`), `OcamlBuilder must not own Sys.${removedField}`)

assert.match(sysSource, /static inline function putEnv\(s:String, v:Null<String>\):Void/)
assert.match(sysSource, /static inline function command\(cmd:String, \?args:Array<String>\):Int/)
assert.match(sysSource, /static inline function setTimeLocale\(loc:String\):Bool/)
for (const nativeField of ['putEnvValue', 'removeEnv', 'commandShell', 'commandArgs'])
	assert(sysSource.includes(`static function ${nativeField}(`), `Sys facade must declare typed NativeHxSys.${nativeField}`)

assert(!hxSysSource.includes('let putEnv ('), 'HxSys must not retain the old option-taking putEnv ABI')
assert(!hxSysSource.includes('let command ('), 'HxSys must not retain the old optional command ABI')
for (const nativeField of ['putEnvValue', 'removeEnv', 'commandShell', 'commandArgs'])
	assert(hxSysSource.includes(`let ${nativeField} (`), `HxSys must implement ${nativeField}`)

assert(!stage3EmitterSource.includes('HxSys.putEnv ('), 'The diagnostic Stage3 emitter must not retain the removed HxSys.putEnv ABI')
for (const nativeField of ['putEnvValue', 'removeEnv'])
	assert(stage3EmitterSource.includes(`HxSys.${nativeField} (`), `The diagnostic Stage3 emitter must use HxSys.${nativeField}`)

console.log('TYPED_HAXE_SYSTEM_RUNTIME_REQUIREMENTS:PASS')
