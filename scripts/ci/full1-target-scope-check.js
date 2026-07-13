#!/usr/bin/env node
/**
 * Keep the first Full1 target promise explicit and consistent.
 *
 * Haxe 4.3.7 exposes more output choices than the current Full1 matrix. This
 * guard makes every public target/generator choice visible, then verifies that
 * the machine-readable promise, strict Gate3 target list, and public docs all
 * describe the same scope.
 */

const fs = require('fs')

const scopePath = 'docs/02-user-guide/compat/full-1.0-scope.json'
const parityMapPath = 'docs/00-project/PARITY_MAP_FULL_1_0.json'
const targetScopeDocPath = 'docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md'
const gate3WorkflowPath = '.github/workflows/gate3-full1-extended.yml'
const gate3RunnerPath = 'scripts/ci/run-gate3-targets-parallel.js'

const requiredDocPaths = [
  'README.md',
  'docs/00-project/NORTH_STAR_GOALS.md',
  'docs/00-project/FULL_1_0_CONTRACT.md',
  'docs/00-project/PARITY_MAP_FULL_1_0.md',
  'docs/00-project/CI_GATES.md',
  'docs/00-project/PUBLIC_1_0_CHECKLIST.md',
  'docs/01-getting-started/HXHX_1_0_ROADMAP.md'
]

const requiredGate3Targets = [
  'Macro',
  'Js',
  'Neko',
  'Hl',
  'Python',
  'Java',
  'Cs',
  'Cpp',
  'Lua',
  'Php'
]

// This list mirrors the public Haxe 4.3.7 Target help plus XML/JSON type
// descriptions. HashLink is split because one flag selects two output forms.
const expectedSurfaces = [
  { id: 'javascript', kind: 'target', flags: ['--js'], disposition: 'required', gate3Target: 'Js' },
  { id: 'lua', kind: 'target', flags: ['--lua'], disposition: 'required', gate3Target: 'Lua' },
  { id: 'flash-swf', kind: 'target', flags: ['--swf'], disposition: 'incompatible' },
  { id: 'neko', kind: 'target', flags: ['--neko'], disposition: 'required', gate3Target: 'Neko' },
  { id: 'php', kind: 'target', flags: ['--php'], disposition: 'required', gate3Target: 'Php' },
  { id: 'cpp', kind: 'target', flags: ['--cpp'], disposition: 'required', gate3Target: 'Cpp' },
  { id: 'cppia', kind: 'target-variant', flags: ['--cppia'], disposition: 'required', gate3Target: 'Cpp' },
  { id: 'csharp', kind: 'target', flags: ['--cs'], disposition: 'required', gate3Target: 'Cs' },
  { id: 'java', kind: 'target', flags: ['--java'], disposition: 'required', gate3Target: 'Java' },
  { id: 'jvm', kind: 'target', flags: ['--jvm'], disposition: 'deferred' },
  { id: 'python', kind: 'target', flags: ['--python'], disposition: 'required', gate3Target: 'Python' },
  { id: 'hashlink-bytecode', kind: 'target-variant', flags: ['--hl <file.hl>'], disposition: 'required', gate3Target: 'Hl' },
  { id: 'hashlink-c', kind: 'target-variant', flags: ['--hl <file.c>'], disposition: 'required', gate3Target: 'Hl' },
  { id: 'interp', kind: 'execution-mode', flags: ['--interp'], disposition: 'required' },
  { id: 'run', kind: 'execution-mode', flags: ['--run'], disposition: 'required' },
  { id: 'xml-type-description', kind: 'generator-service', flags: ['--xml'], disposition: 'deferred' },
  { id: 'json-type-description', kind: 'generator-service', flags: ['--json'], disposition: 'deferred' }
]

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, 'utf8'))
}

function sameOrdered(left, right) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => value === right[index])
}

/** Return every contract mismatch so one guard run gives a complete repair list. */
function validateTargetScope(input) {
  const errors = []
  const { scope, parityMap, workflowText, runnerText, targetDocText, docs } = input
  if (scope.contractVersion !== '1.1.0' || parityMap.contractVersion !== '1.1.0') {
    errors.push('scope and parity-map contractVersion must both be 1.1.0')
  }
  if (scope.haxeCompatibilityBaseline !== '4.3.7' || parityMap.haxeCompatibilityBaseline !== '4.3.7') {
    errors.push('scope and parity map must both use the Haxe 4.3.7 baseline')
  }
  const targetScope = scope && scope.full && scope.full.targetAndGeneratorScope
  if (!targetScope || typeof targetScope !== 'object') {
    return ['scope manifest must define full.targetAndGeneratorScope']
  }
  if (targetScope.plainLanguageDoc !== targetScopeDocPath) {
    errors.push(`full.targetAndGeneratorScope.plainLanguageDoc must be ${targetScopeDocPath}`)
  }
  if (targetScope.publicClaim !== 'Haxe 4.3.7-compatible for the declared Full1 target and generator scope.') {
    errors.push('target scope must retain the approved, qualified public claim wording')
  }
  if (!sameOrdered(targetScope.requiredGate3Targets, requiredGate3Targets)) {
    errors.push(`requiredGate3Targets must be exactly ${requiredGate3Targets.join(',')}`)
  }
  if (!Array.isArray(targetScope.surfaces)) {
    return errors.concat('full.targetAndGeneratorScope.surfaces must be an array')
  }

  const surfacesById = new Map()
  for (const surface of targetScope.surfaces) {
    if (!surface || typeof surface.id !== 'string' || surface.id.length === 0) {
      errors.push('every target/generator surface must have a non-empty id')
      continue
    }
    if (surfacesById.has(surface.id)) errors.push(`duplicate target/generator surface id: ${surface.id}`)
    surfacesById.set(surface.id, surface)
  }
  if (surfacesById.size !== expectedSurfaces.length) {
    errors.push(`target/generator inventory must contain exactly ${expectedSurfaces.length} surfaces`)
  }

  const parityMarkers = new Set((parityMap.entries || []).map(entry => entry && entry.marker).filter(Boolean))
  const requiredMarkers = new Set(Array.isArray(scope.full.requiredMarkersPlanned)
    ? scope.full.requiredMarkersPlanned
    : [])
  for (const expected of expectedSurfaces) {
    const surface = surfacesById.get(expected.id)
    if (!surface) {
      errors.push(`missing Haxe 4.3.7 target/generator surface: ${expected.id}`)
      continue
    }
    if (surface.kind !== expected.kind) errors.push(`${expected.id}: kind must be ${expected.kind}`)
    if (surface.disposition !== expected.disposition) {
      errors.push(`${expected.id}: disposition must be ${expected.disposition}`)
    }
    if (!sameOrdered(surface.upstreamFlags, expected.flags)) {
      errors.push(`${expected.id}: upstreamFlags must be exactly ${expected.flags.join(', ')}`)
    }
    if (expected.gate3Target && surface.gate3Target !== expected.gate3Target) {
      errors.push(`${expected.id}: gate3Target must be ${expected.gate3Target}`)
    }
    for (const field of ['label', 'rationale', 'userConsequence']) {
      if (typeof surface[field] !== 'string' || surface[field].trim().length === 0) {
        errors.push(`${expected.id}: ${field} must explain the decision in plain language`)
      }
    }
    if (!Array.isArray(surface.evidenceMarkers)) {
      errors.push(`${expected.id}: evidenceMarkers must be an array`)
    } else if (surface.disposition === 'required') {
      if (surface.evidenceMarkers.length === 0) errors.push(`${expected.id}: required surfaces need evidence markers`)
      for (const marker of surface.evidenceMarkers) {
        if (!parityMarkers.has(marker)) errors.push(`${expected.id}: evidence marker is absent from parity map: ${marker}`)
        if (!requiredMarkers.has(marker)) errors.push(`${expected.id}: evidence marker is absent from the Full1 required marker list: ${marker}`)
      }
    } else if (surface.evidenceMarkers.length !== 0) {
      errors.push(`${expected.id}: deferred/incompatible surfaces cannot claim passing evidence markers`)
    }
    if (!targetDocText.includes(surface.label)) {
      errors.push(`${targetScopeDocPath} must describe ${surface.label}`)
    }
  }
  for (const id of surfacesById.keys()) {
    if (!expectedSurfaces.some(surface => surface.id === id)) errors.push(`unexpected target/generator surface: ${id}`)
  }

  const coveredGate3Targets = new Set(targetScope.surfaces
    .filter(surface => surface.disposition === 'required' && surface.gate3Target)
    .map(surface => surface.gate3Target))
  for (const target of requiredGate3Targets.slice(1)) {
    if (!coveredGate3Targets.has(target)) errors.push(`required Gate3 target has no required public surface: ${target}`)
  }
  for (const target of coveredGate3Targets) {
    if (!requiredGate3Targets.includes(target)) errors.push(`public surface maps to undeclared Gate3 target: ${target}`)
  }

  const gate3Entry = (parityMap.entries || []).find(entry => entry && entry.marker === 'FULL1_GATE3_EXTENDED_TARGETS:PASS')
  if (!gate3Entry || !sameOrdered(gate3Entry.targets, requiredGate3Targets)) {
    errors.push('parity map Gate3 entry must use the exact requiredGate3Targets order')
  }
  const scopeEntry = (parityMap.entries || []).find(entry => entry && entry.marker === 'FULL1_TARGET_SCOPE_CONTRACT:PASS')
  if (!scopeEntry || scopeEntry.workflow !== 'scripts/ci/full1-target-scope-check.js' || scopeEntry.enforcement !== 'required_now') {
    errors.push('parity map must register FULL1_TARGET_SCOPE_CONTRACT:PASS as required_now')
  }
  if (!Array.isArray(scope.full.requiredMarkersPlanned)
    || !scope.full.requiredMarkersPlanned.includes('FULL1_TARGET_SCOPE_CONTRACT:PASS')) {
    errors.push('scope manifest must require FULL1_TARGET_SCOPE_CONTRACT:PASS')
  }

  const joinedTargets = requiredGate3Targets.join(',')
  if (!workflowText.includes(`default: "${joinedTargets}"`)) {
    errors.push(`${gate3WorkflowPath} default target input must match requiredGate3Targets`)
  }
  if (!workflowText.includes(`inputs.targets || '${joinedTargets}'`)) {
    errors.push(`${gate3WorkflowPath} fallback target input must match requiredGate3Targets`)
  }
  if (!runnerText.includes(`const DEFAULT_TARGETS = '${joinedTargets}'`)) {
    errors.push(`${gate3RunnerPath} default target list must match requiredGate3Targets`)
  }
  for (const path of requiredDocPaths) {
    if (!docs[path] || !docs[path].includes(targetScopeDocPath)) {
      errors.push(`${path} must reference ${targetScopeDocPath}`)
    }
  }
  return errors
}

function main() {
  const allPaths = [
    scopePath,
    parityMapPath,
    targetScopeDocPath,
    gate3WorkflowPath,
    gate3RunnerPath,
    ...requiredDocPaths
  ]
  const missing = allPaths.filter(path => !fs.existsSync(path))
  if (missing.length > 0) {
    for (const path of missing) console.error(`[ci:guards] ERROR: missing target-scope path: ${path}`)
    process.exit(1)
  }
  const docs = Object.fromEntries(requiredDocPaths.map(path => [path, fs.readFileSync(path, 'utf8')]))
  const errors = validateTargetScope({
    scope: readJson(scopePath),
    parityMap: readJson(parityMapPath),
    workflowText: fs.readFileSync(gate3WorkflowPath, 'utf8'),
    runnerText: fs.readFileSync(gate3RunnerPath, 'utf8'),
    targetDocText: fs.readFileSync(targetScopeDocPath, 'utf8'),
    docs
  })
  if (errors.length > 0) {
    for (const error of errors) console.error(`[ci:guards] ERROR: ${error}`)
    process.exit(1)
  }
  console.log('[ci:guards] OK: Full1 target/generator scope is explicit and synchronized')
  console.log('FULL1_TARGET_SCOPE_CONTRACT:PASS')
}

if (require.main === module) main()

module.exports = {
  expectedSurfaces,
  requiredDocPaths,
  requiredGate3Targets,
  validateTargetScope
}
