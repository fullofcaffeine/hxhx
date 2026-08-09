const assert = require('node:assert/strict')

/**
 * Models the current module-name comparison without importing compiler code.
 *
 * The real report reduces every structured `HxArray.set` reference to the
 * module name `HxArray`. This small model deliberately keeps that behavior so
 * the design review can demonstrate the missing information: two distinct
 * planned uses cannot be distinguished from one planned use emitted twice.
 */
function currentModuleAuthority(plannedRequirements, emittedReferences) {
	const requirementRoots = [...new Set(plannedRequirements.map(item => item.module))].sort()
	const observedModules = [...new Set(emittedReferences.map(item => item.module))].sort()
	return {
		requirementRoots,
		observedModules,
		withoutRequirementRoot: observedModules.filter(module => !requirementRoots.includes(module))
	}
}

const planned = [
	{ requirementId: 'R-array', useId: 'U1', module: 'HxArray', symbol: 'HxArray.set' },
	{ requirementId: 'R-array', useId: 'U2', module: 'HxArray', symbol: 'HxArray.set' }
]

const valid = currentModuleAuthority(planned, [planned[0], planned[1]])
const duplicatedSecondUse = currentModuleAuthority(planned, [planned[1], planned[1]])

console.log(JSON.stringify({ valid, duplicatedSecondUse }, null, 2))

// This is intentionally red with the current authority model. A future
// occurrence-aware reconciler must make the two results observably different:
// the corrupted output is missing U1 and duplicates U2.
assert.notDeepStrictEqual(duplicatedSecondUse, valid)
