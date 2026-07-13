#!/usr/bin/env node
/** Focused mutation tests for the Full1 target/generator scope guard. */

const assert = require('assert')
const fs = require('fs')
const {
  requiredDocPaths,
  validateTargetScope
} = require('./full1-target-scope-check')

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, 'utf8'))
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function baseInput() {
  return {
    scope: readJson('docs/02-user-guide/compat/full-1.0-scope.json'),
    parityMap: readJson('docs/00-project/PARITY_MAP_FULL_1_0.json'),
    workflowText: fs.readFileSync('.github/workflows/gate3-full1-extended.yml', 'utf8'),
    runnerText: fs.readFileSync('scripts/ci/run-gate3-targets-parallel.js', 'utf8'),
    targetDocText: fs.readFileSync('docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md', 'utf8'),
    docs: Object.fromEntries(requiredDocPaths.map(path => [path, fs.readFileSync(path, 'utf8')]))
  }
}

function expectError(input, snippet) {
  const errors = validateTargetScope(input)
  assert(errors.some(error => error.includes(snippet)), `expected error containing ${JSON.stringify(snippet)}\n${errors.join('\n')}`)
}

function main() {
  const valid = baseInput()
  assert.deepStrictEqual(validateTargetScope(valid), [])

  const missingJvm = clone(valid)
  missingJvm.scope.full.targetAndGeneratorScope.surfaces = missingJvm.scope.full.targetAndGeneratorScope.surfaces
    .filter(surface => surface.id !== 'jvm')
  expectError(missingJvm, 'missing Haxe 4.3.7 target/generator surface: jvm')

  const weakenedCppia = clone(valid)
  weakenedCppia.scope.full.targetAndGeneratorScope.surfaces.find(surface => surface.id === 'cppia').disposition = 'deferred'
  expectError(weakenedCppia, 'cppia: disposition must be required')

  const missingGateTarget = clone(valid)
  missingGateTarget.parityMap.entries.find(entry => entry.marker === 'FULL1_GATE3_EXTENDED_TARGETS:PASS').targets = [
    'Macro', 'Js', 'Neko', 'Hl', 'Python', 'Java', 'Cs', 'Lua', 'Php'
  ]
  expectError(missingGateTarget, 'parity map Gate3 entry must use the exact requiredGate3Targets order')

  const undocumented = clone(valid)
  undocumented.docs['README.md'] = undocumented.docs['README.md'].replace(
    'docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md',
    'missing-scope-link'
  )
  expectError(undocumented, 'README.md must reference')

  const invented = clone(valid)
  invented.scope.full.targetAndGeneratorScope.surfaces.push({
    id: 'invented-target',
    label: 'Invented output',
    kind: 'target',
    upstreamFlags: ['--invented'],
    disposition: 'required',
    gate3Target: 'Invented',
    evidenceMarkers: ['FULL1_GATE3_EXTENDED_TARGETS:PASS'],
    rationale: 'fixture',
    userConsequence: 'fixture'
  })
  expectError(invented, 'unexpected target/generator surface: invented-target')

  console.log('[full1-target-scope-check-fixture-test] ok')
}

main()
