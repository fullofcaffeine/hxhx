'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

/**
 * Proves that each thread fixture packages HxThread for the typed Haxe
 * operations emitted by that program, rather than for a generated-name match.
 */
const expectedFieldsByFixture = {
	sys_thread_bucket01_basic: [
		'condition_acquire',
		'condition_broadcast',
		'condition_create',
		'condition_release',
		'condition_signal',
		'condition_try_acquire',
		'condition_wait',
		'deque_add',
		'deque_create',
		'deque_pop',
		'deque_push',
		'lock_create',
		'lock_release',
		'lock_wait',
		'lock_wait_timeout',
		'mutex_acquire',
		'mutex_create',
		'mutex_release',
		'mutex_try_acquire',
		'semaphore_acquire',
		'semaphore_create',
		'semaphore_release',
		'semaphore_try_acquire',
		'semaphore_try_acquire_timeout',
		'thread_create',
		'thread_current',
		'thread_get_events',
		'thread_read_message',
		'thread_send_message',
		'thread_set_events',
	],
	sys_thread_bucket02_tls: [
		'lock_create',
		'lock_release',
		'lock_wait',
		'lock_wait_timeout',
		'mutex_acquire',
		'mutex_create',
		'mutex_release',
		'mutex_try_acquire',
		'thread_create',
		'thread_current',
		'thread_get_events',
		'thread_read_message',
		'thread_send_message',
		'thread_set_events',
		'tls_create',
		'tls_get',
		'tls_set',
	],
}
const fixture = path.basename(process.cwd())
const expectedFields = expectedFieldsByFixture[fixture]
assert(expectedFields, `No typed Haxe thread requirement contract is declared for ${fixture}`)

const report = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
const owner = 'sys.thread.NativeHxThread::sys.thread.NativeHxThread'
const requirements = report.requirements
	.filter((requirement) => requirement.semanticCapability === 'haxe-thread')
	.sort((left, right) => left.id.localeCompare(right.id))
const requirementsById = new Map(requirements.map((requirement) => [requirement.id, requirement]))

assert(report.compilerObservedModulesWithRequirementRoots.includes('HxThread'), 'HxThread must overlap an explicit requirement root')
assert(!report.compilerObservedModulesWithoutRequirementRoots.includes('HxThread'), 'HxThread must not remain in the unrooted module set')
assert.equal(requirementsById.size, expectedFields.length)

for (const field of expectedFields) {
	const id = `native:${owner}.${field}:runtime:haxe-thread`
	const requirement = requirementsById.get(id)
	assert(requirement, `Missing typed Haxe thread runtime requirement ${id}`)
	assert.equal(requirement.sourceKind, 'native-boundary')
	assert.equal(requirement.cause, 'native-boundary')
	assert.equal(requirement.implementationFeature, 'haxe-thread-v1')
	assert.deepEqual(requirement.rootModules, ['HxThread'])
	assert.deepEqual(requirement.profileEligibility, ['metal', 'portable'])
	assert.deepEqual(requirement.subject, {
		id: `${owner}.${field} -> HxThread.${field}`,
		kind: 'native-boundary',
	})
}

console.log(`TYPED_HAXE_THREAD_RUNTIME_REQUIREMENTS:PASS fixture=${fixture} operations=${requirements.length}`)
