'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')

/**
 * Proves that typed Haxe file and stream operations explain HxFile and
 * HxFileStream, while the separately owned FileSystem bridge remains visible
 * as unrooted compiler output.
 */
const report = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
const expectedBoundaries = [
	['haxe-file', 'sys.io.File', 'sys.io._File.NativeHxFile', 'copy', 'HxFile', 'haxe-file-v1'],
	['haxe-file', 'sys.io.File', 'sys.io._File.NativeHxFile', 'getBytes', 'HxFile', 'haxe-file-v1'],
	['haxe-file', 'sys.io.File', 'sys.io._File.NativeHxFile', 'getContent', 'HxFile', 'haxe-file-v1'],
	['haxe-file', 'sys.io.File', 'sys.io._File.NativeHxFile', 'saveBytes', 'HxFile', 'haxe-file-v1'],
	['haxe-file', 'sys.io.File', 'sys.io._File.NativeHxFile', 'saveContent', 'HxFile', 'haxe-file-v1'],
	['haxe-file-stream', 'sys.io.File', 'sys.io._File.NativeHxFileStream', 'open_in', 'HxFileStream', 'haxe-file-stream-v1'],
	['haxe-file-stream', 'sys.io.File', 'sys.io._File.NativeHxFileStream', 'open_out', 'HxFileStream', 'haxe-file-stream-v1'],
	[
		'haxe-file-stream',
		'sys.io.FileInput',
		'sys.io._FileInput.NativeHxFileStream',
		'close_in',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileInput',
		'sys.io._FileInput.NativeHxFileStream',
		'eof_in',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileInput',
		'sys.io._FileInput.NativeHxFileStream',
		'read_byte',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileInput',
		'sys.io._FileInput.NativeHxFileStream',
		'seek_in',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileInput',
		'sys.io._FileInput.NativeHxFileStream',
		'tell_in',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileOutput',
		'sys.io._FileOutput.NativeHxFileStream',
		'close_out',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileOutput',
		'sys.io._FileOutput.NativeHxFileStream',
		'flush_out',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileOutput',
		'sys.io._FileOutput.NativeHxFileStream',
		'seek_out',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileOutput',
		'sys.io._FileOutput.NativeHxFileStream',
		'tell_out',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
	[
		'haxe-file-stream',
		'sys.io.FileOutput',
		'sys.io._FileOutput.NativeHxFileStream',
		'write_byte',
		'HxFileStream',
		'haxe-file-stream-v1',
	],
]
const requirements = report.requirements
	.filter((requirement) => requirement.semanticCapability === 'haxe-file' || requirement.semanticCapability === 'haxe-file-stream')
	.sort((left, right) => left.id.localeCompare(right.id))

assert(report.compilerObservedModulesWithRequirementRoots.includes('HxFile'), 'HxFile must overlap an explicit requirement root')
assert(report.compilerObservedModulesWithRequirementRoots.includes('HxFileStream'), 'HxFileStream must overlap an explicit requirement root')
assert(!report.compilerObservedModulesWithoutRequirementRoots.includes('HxFile'), 'HxFile must not remain in the unrooted module set')
assert(!report.compilerObservedModulesWithoutRequirementRoots.includes('HxFileStream'), 'HxFileStream must not remain in the unrooted module set')
assert(
	report.compilerObservedModulesWithoutRequirementRoots.includes('HxFileSystem'),
	'HxFileSystem must remain visible until its separate typed semantic boundary is sealed'
)
assert.equal(requirements.length, expectedBoundaries.length)

for (const [index, requirement] of requirements.entries()) {
	const [capability, owner, nativeType, field, rootModule, feature] = expectedBoundaries[index]
	const boundary = `${owner}::${nativeType}.${field}`
	assert.equal(requirement.id, `native:${boundary}:runtime:${capability}`)
	assert.equal(requirement.sourceKind, 'native-boundary')
	assert.equal(requirement.cause, 'native-boundary')
	assert.equal(requirement.implementationFeature, feature)
	assert.deepEqual(requirement.rootModules, [rootModule])
	assert.deepEqual(requirement.profileEligibility, ['metal', 'portable'])
	assert.deepEqual(requirement.subject, {
		id: `${boundary} -> ${rootModule}.${field}`,
		kind: 'native-boundary',
	})
}

console.log('TYPED_HAXE_FILE_RUNTIME_REQUIREMENTS:PASS')
