#!/usr/bin/env node
/**
 * Build the candidate-bound Full1 RC decision from verified evidence metadata.
 *
 * This evaluator never accepts marker strings on the command line. Each
 * marker must come from a validated artifact role in the evidence index, and
 * aggregate markers are derived from their required child roles.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const scopePath = path.join(root, 'docs/02-user-guide/compat/full-1.0-scope.json')
const parityMapPath = path.join(root, 'docs/00-project/PARITY_MAP_FULL_1_0.json')
const releaseMarker = 'FULL1_RELEASE_GO:PASS'
const failureMarker = 'FULL1_RELEASE_GO:FAIL'

const rolePolicy = {
  policy: {
    tier: 1,
    markers: [
      'FULL1_TARGET_SCOPE_CONTRACT:PASS',
      'FULL1_PARITY_MAP:PASS',
      'FULL1_MACRO_EVAL_CONTRACT:PASS',
      'FULL1_PLUGIN_PARITY_CONTRACT:PASS',
      'FULL1_FLAKE_POLICY:PASS',
      'FULL1_PERF_POLICY:PASS'
    ]
  },
  gate3: {
    tier: 7,
    markers: ['FULL1_GATE3_EXTENDED_TARGETS:PASS']
  },
  suite: {
    tier: 7,
    markers: [
      'FULL1_SUITE_MISC:PASS',
      'FULL1_SUITE_SERVER:PASS',
      'FULL1_SUITE_THREADS:PASS',
      'FULL1_SUITE_OPTIMIZATION:PASS',
      'FULL1_SUITE_DISPLAY:PASS'
    ]
  },
  macro: {
    tier: 7,
    markers: ['FULL1_MACRO_PARITY:PASS']
  },
  eval: {
    tier: 7,
    markers: ['FULL1_EVAL_NATIVE:PASS']
  },
  plugin: {
    tier: 8,
    markers: ['FULL1_PLUGIN_PARITY:PASS']
  },
  performance: {
    tier: 9,
    markers: ['FULL1_PERF_PARITY:PASS']
  }
}

// One source record is accepted for each named role below. Keeping this exact
// prevents a broad role (for example `suite`) from claiming several markers.
const evidenceContracts = {
  policy: {
    role: 'policy',
    workflowFile: '.github/workflows/gate-full1-rc.yml',
    artifactPrefix: 'full1-rc-policy',
    summarySchema: 'full1-rc-policy-evidence.v1',
    markers: rolePolicy.policy.markers
  },
  gate3: {
    role: 'gate3',
    workflowFile: '.github/workflows/gate3-full1-extended.yml',
    artifactPrefix: 'full1-gate3-extended',
    summarySchema: 'gate3-extended-summary.v1',
    markers: rolePolicy.gate3.markers
  },
  'suite-misc': {
    role: 'suite',
    workflowFile: '.github/workflows/full1-suite-runners.yml',
    artifactPrefix: 'full1-suite-misc',
    summarySchema: 'full1-upstream-suite-summary.v1',
    markers: ['FULL1_SUITE_MISC:PASS']
  },
  'suite-server': {
    role: 'suite',
    workflowFile: '.github/workflows/full1-suite-runners.yml',
    artifactPrefix: 'full1-suite-server',
    summarySchema: 'full1-upstream-suite-summary.v1',
    markers: ['FULL1_SUITE_SERVER:PASS']
  },
  'suite-threads': {
    role: 'suite',
    workflowFile: '.github/workflows/full1-suite-runners.yml',
    artifactPrefix: 'full1-suite-threads',
    summarySchema: 'full1-upstream-suite-summary.v1',
    markers: ['FULL1_SUITE_THREADS:PASS']
  },
  'suite-optimization': {
    role: 'suite',
    workflowFile: '.github/workflows/full1-suite-runners.yml',
    artifactPrefix: 'full1-suite-optimization',
    summarySchema: 'full1-upstream-suite-summary.v1',
    markers: ['FULL1_SUITE_OPTIMIZATION:PASS']
  },
  'suite-display': {
    role: 'suite',
    workflowFile: '.github/workflows/full1-suite-runners.yml',
    artifactPrefix: 'full1-suite-display',
    summarySchema: 'full1-upstream-suite-summary.v1',
    markers: ['FULL1_SUITE_DISPLAY:PASS']
  },
  macro: {
    role: 'macro',
    workflowFile: '.github/workflows/macro-runtime-parity-weekly.yml',
    artifactPrefix: 'macro-runtime-parity-summary',
    summarySchema: 'macro-runtime-parity-summary.v3',
    markers: rolePolicy.macro.markers
  },
  eval: {
    role: 'eval',
    workflowFile: '.github/workflows/full1-eval-native.yml',
    artifactPrefix: 'full1-eval-native',
    summarySchema: 'full1-eval-native-summary.v1',
    markers: rolePolicy.eval.markers
  },
  plugin: {
    role: 'plugin',
    workflowFile: '.github/workflows/full1-plugin-parity.yml',
    artifactPrefix: 'full1-plugin-parity-summary',
    summarySchema: 'full1-plugin-parity-summary.v3',
    markers: rolePolicy.plugin.markers
  },
  performance: {
    role: 'performance',
    workflowFile: '.github/workflows/gate-perf-full1.yml',
    artifactPrefix: 'full1-perf-evaluated',
    summarySchema: 'full1-perf-evaluation.v1',
    markers: rolePolicy.performance.markers
  }
}

function fail(message) {
  console.error(`[full1-rc-gate] ${message}`)
  process.exit(1)
}

function usage() {
  return [
    'Usage: node scripts/ci/full1-rc-gate.js',
    '  --evidence-index <path>',
    '  --candidate-sha <40-char-sha>',
    '  --candidate-version <semver>',
    '  --run-id <github-run-id>',
    '  --run-attempt <attempt>',
    '  --json-out <path>',
    '  [--now <iso-timestamp>]',
    '  [--max-age-hours <hours>]'
  ].join('\n')
}

function parseArgs(argv) {
  const args = {
    evidenceIndex: '',
    candidateSha: '',
    candidateVersion: '',
    runId: 0,
    runAttempt: 0,
    jsonOut: '',
    now: new Date().toISOString(),
    maxAgeHours: 24
  }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--help' || arg === '-h') {
      console.log(usage())
      process.exit(0)
    } else if (arg === '--evidence-index') args.evidenceIndex = argv[++i] || ''
    else if (arg === '--candidate-sha') args.candidateSha = argv[++i] || ''
    else if (arg === '--candidate-version') args.candidateVersion = argv[++i] || ''
    else if (arg === '--run-id') args.runId = Number(argv[++i])
    else if (arg === '--run-attempt') args.runAttempt = Number(argv[++i])
    else if (arg === '--json-out') args.jsonOut = argv[++i] || ''
    else if (arg === '--now') args.now = argv[++i] || ''
    else if (arg === '--max-age-hours') args.maxAgeHours = Number(argv[++i])
    else fail(`unknown argument: ${arg}\n${usage()}`)
  }
  if (!args.evidenceIndex || !args.jsonOut || !args.candidateSha || !args.candidateVersion) {
    fail(`missing required argument\n${usage()}`)
  }
  if (!Number.isInteger(args.runId) || args.runId <= 0) fail('--run-id must be a positive integer')
  if (!Number.isInteger(args.runAttempt) || args.runAttempt <= 0) {
    fail('--run-attempt must be a positive integer')
  }
  if (!Number.isFinite(args.maxAgeHours) || args.maxAgeHours <= 0) {
    fail('--max-age-hours must be positive')
  }
  if (!/^[0-9a-f]{40}$/i.test(args.candidateSha)) {
    fail('--candidate-sha must be a full 40-character SHA')
  }
  if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(args.candidateVersion)) {
    fail('--candidate-version must be valid semver without a v prefix')
  }
  if (Number.isNaN(Date.parse(args.now))) fail('--now must be an ISO timestamp')
  return args
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    fail(`failed to read JSON ${path.relative(root, filePath)}: ${error.message}`)
  }
}

function sha256File(filePath) {
  return `sha256:${crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')}`
}

function fullScopeMarkers(scope) {
  const planned = scope && scope.full && scope.full.requiredMarkersPlanned
  if (!Array.isArray(planned) || planned.length === 0) {
    fail(`${path.relative(root, scopePath)} must define full.requiredMarkersPlanned[]`)
  }
  if (!planned.includes(releaseMarker)) {
    fail(`${path.relative(root, scopePath)} must include ${releaseMarker}`)
  }
  return planned.filter(marker => marker !== releaseMarker)
}

function validateParityMap(requiredMarkers, parityMap) {
  if (!Array.isArray(parityMap.entries) || parityMap.entries.length === 0) {
    fail(`${path.relative(root, parityMapPath)} must define entries[]`)
  }
  const entriesByMarker = new Map()
  for (const entry of parityMap.entries) {
    if (entry && entry.marker) entriesByMarker.set(entry.marker, entry)
  }
  const missingEntries = requiredMarkers.filter(marker => !entriesByMarker.has(marker))
  if (missingEntries.length > 0) {
    fail(`required Full1 markers missing from parity map: ${missingEntries.join(', ')}`)
  }
  const releaseEntry = entriesByMarker.get(releaseMarker)
  if (!releaseEntry) fail(`${path.relative(root, parityMapPath)} must include ${releaseMarker}`)
  if (releaseEntry.workflow !== '.github/workflows/gate-full1-rc.yml') {
    fail(`${releaseMarker} must be owned by .github/workflows/gate-full1-rc.yml`)
  }
}

function writeSummary(jsonOut, summary) {
  const resolved = path.resolve(jsonOut)
  fs.mkdirSync(path.dirname(resolved), { recursive: true })
  fs.writeFileSync(resolved, `${JSON.stringify(summary, null, 2)}\n`)
}

function validTimestamp(value) {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value))
}

function sameMembers(left, right) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every(value => right.includes(value))
}

/** Recheck one collector record against its fixed role, candidate, and age. */
function evaluateSource(source, args, nowMs) {
  const errors = []
  const policy = rolePolicy[source.role]
  const contract = evidenceContracts[source.id]
  if (!policy) errors.push(`unknown evidence role: ${source.role}`)
  if (!source.id || typeof source.id !== 'string') errors.push('source id is required')
  if (!contract) errors.push(`unknown evidence source id: ${source.id}`)
  else {
    if (source.role !== contract.role) errors.push(`${source.id}: role does not match its evidence contract`)
    if (source.workflowFile !== contract.workflowFile) {
      errors.push(`${source.id}: workflow file does not match its evidence contract`)
    }
    const expectedArtifactName = `${contract.artifactPrefix}-${args.runId}-${args.runAttempt}`
    if (source.artifactName !== expectedArtifactName) {
      errors.push(`${source.id}: artifact name must be ${expectedArtifactName}`)
    }
    if (!sameMembers(source.markers, contract.markers)) {
      errors.push(`${source.id}: marker set does not match its evidence contract`)
    }
    if (!source.summary || source.summary.schema !== contract.summarySchema) {
      errors.push(`${source.id}: summary schema must be ${contract.summarySchema}`)
    }
  }
  if (source.synthetic !== false) errors.push('synthetic evidence is forbidden')
  if (source.valid !== true) errors.push('collector did not validate this artifact')
  if (source.workflowConclusion !== 'success') {
    errors.push(`workflow conclusion must be success, received ${source.workflowConclusion}`)
  }
  if (source.runId !== args.runId || source.runAttempt !== args.runAttempt) {
    errors.push('source run/attempt does not match the RC workflow')
  }
  if (source.headSha !== args.candidateSha) errors.push('source SHA does not match the candidate')
  if (!Number.isInteger(source.artifactId) || source.artifactId <= 0) {
    errors.push('artifactId must be a positive integer')
  }
  if (!source.artifactName || typeof source.artifactName !== 'string') {
    errors.push('artifactName is required')
  }
  if (!/^sha256:[0-9a-f]{64}$/i.test(String(source.artifactDigest || ''))) {
    errors.push('artifactDigest must be a SHA-256 digest')
  }
  if (!validTimestamp(source.createdAt)) errors.push('createdAt must be an ISO timestamp')
  else {
    const ageHours = (nowMs - Date.parse(source.createdAt)) / 3600000
    if (ageHours < 0) errors.push('artifact timestamp is in the future')
    if (ageHours > args.maxAgeHours) errors.push(`artifact is stale (${ageHours.toFixed(2)}h old)`)
  }
  if (!validTimestamp(source.expiresAt)) errors.push('expiresAt must be an ISO timestamp')
  else if (Date.parse(source.expiresAt) <= nowMs) errors.push('artifact is expired')
  if (!source.summary || typeof source.summary !== 'object') errors.push('summary metadata is required')
  else {
    if (!source.summary.path || typeof source.summary.path !== 'string') {
      errors.push('summary.path is required')
    }
    if (!/^sha256:[0-9a-f]{64}$/i.test(String(source.summary.digest || ''))) {
      errors.push('summary.digest must be a SHA-256 digest')
    }
    if (!source.summary.schema || typeof source.summary.schema !== 'string') {
      errors.push('summary.schema is required')
    }
  }
  if (!Array.isArray(source.markers) || source.markers.length === 0) {
    errors.push('markers[] must be non-empty')
  }
  if (policy) {
    if (source.evidenceTier !== policy.tier) {
      errors.push(`role ${source.role} requires evidenceTier ${policy.tier}`)
    }
    for (const marker of source.markers || []) {
      if (!policy.markers.includes(marker)) {
        errors.push(`role ${source.role} cannot emit ${marker}`)
      }
    }
  }
  return {
    ...source,
    errors,
    accepted: errors.length === 0
  }
}

/** Derive aggregate claims only after every lower-level claim is accepted. */
function deriveMarkers(sourceEvaluations) {
  const direct = new Set()
  const markerSources = {}
  for (const source of sourceEvaluations) {
    if (!source.accepted) continue
    for (const marker of source.markers) {
      direct.add(marker)
      if (!markerSources[marker]) markerSources[marker] = []
      markerSources[marker].push(source.id)
    }
  }

  const derived = []
  const addDerived = (marker, requires) => {
    if (!requires.every(required => direct.has(required))) return
    direct.add(marker)
    markerSources[marker] = requires.flatMap(required => markerSources[required] || [])
    derived.push({ marker, requires, sourceIds: markerSources[marker] })
  }
  addDerived('FULL1_SUITE_MATRIX:PASS', [
    'FULL1_GATE3_EXTENDED_TARGETS:PASS',
    'FULL1_SUITE_MISC:PASS',
    'FULL1_SUITE_SERVER:PASS',
    'FULL1_SUITE_THREADS:PASS',
    'FULL1_SUITE_OPTIMIZATION:PASS',
    'FULL1_SUITE_DISPLAY:PASS'
  ])
  addDerived('FULL1_MACRO_EVAL_PARITY:PASS', [
    'FULL1_MACRO_PARITY:PASS',
    'FULL1_EVAL_NATIVE:PASS'
  ])
  return { markers: direct, markerSources, derived }
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const scope = readJson(scopePath)
  const parityMap = readJson(parityMapPath)
  const evidenceIndex = readJson(path.resolve(args.evidenceIndex))
  const requiredMarkers = fullScopeMarkers(scope)
  validateParityMap(requiredMarkers, parityMap)

  const errors = []
  const scopeDigest = sha256File(scopePath)
  const parityMapDigest = sha256File(parityMapPath)
  if (evidenceIndex.schema !== 'full1-rc-evidence-index.v1') {
    errors.push('evidence index schema must be full1-rc-evidence-index.v1')
  }
  if (evidenceIndex.synthetic !== false) errors.push('evidence index must declare synthetic=false')
  if (!evidenceIndex.candidate || evidenceIndex.candidate.sha !== args.candidateSha) {
    errors.push('evidence index candidate SHA mismatch')
  }
  if (!evidenceIndex.candidate || evidenceIndex.candidate.version !== args.candidateVersion) {
    errors.push('evidence index candidate version mismatch')
  }
  if (!evidenceIndex.rcWorkflow
    || evidenceIndex.rcWorkflow.runId !== args.runId
    || evidenceIndex.rcWorkflow.runAttempt !== args.runAttempt) {
    errors.push('evidence index RC run identity mismatch')
  }
  if (!evidenceIndex.contract
    || evidenceIndex.contract.scopeManifestDigest !== scopeDigest
    || evidenceIndex.contract.parityMapDigest !== parityMapDigest) {
    errors.push('evidence index manifest digest mismatch')
  }
  if (!Array.isArray(evidenceIndex.missingArtifacts)) errors.push('missingArtifacts[] is required')
  else if (evidenceIndex.missingArtifacts.length > 0) {
    errors.push(`missing artifacts: ${evidenceIndex.missingArtifacts.join(', ')}`)
  }
  if (!Array.isArray(evidenceIndex.invalidArtifacts)) errors.push('invalidArtifacts[] is required')
  else if (evidenceIndex.invalidArtifacts.length > 0) {
    errors.push(`invalid artifacts: ${evidenceIndex.invalidArtifacts.join(', ')}`)
  }
  if (!Array.isArray(evidenceIndex.sources)) errors.push('sources[] is required')

  const nowMs = Date.parse(args.now)
  const sourceEvaluations = (evidenceIndex.sources || []).map(source => (
    evaluateSource(source, args, nowMs)
  ))
  for (const source of sourceEvaluations) {
    for (const sourceError of source.errors) errors.push(`${source.id || '<source>'}: ${sourceError}`)
  }
  const sourceIds = new Set()
  for (const source of sourceEvaluations) {
    if (sourceIds.has(source.id)) errors.push(`duplicate evidence source id: ${source.id}`)
    sourceIds.add(source.id)
  }

  const derived = deriveMarkers(sourceEvaluations)
  const presentMarkers = requiredMarkers.filter(marker => derived.markers.has(marker))
  const missingMarkers = requiredMarkers.filter(marker => !derived.markers.has(marker))
  if (missingMarkers.length > 0) errors.push(`missing ${missingMarkers.length} required marker(s)`)
  const decision = errors.length === 0 ? 'go' : 'no-go'
  const summary = {
    schema: 'full1-rc-summary.v2',
    evidenceTier: 10,
    synthetic: false,
    decision,
    marker: decision === 'go' ? releaseMarker : failureMarker,
    candidate: {
      sha: args.candidateSha,
      version: args.candidateVersion
    },
    contract: {
      contractVersion: scope.contractVersion,
      haxeCompatibilityBaseline: scope.haxeCompatibilityBaseline,
      scopeManifest: path.relative(root, scopePath),
      scopeManifestDigest: scopeDigest,
      parityMap: path.relative(root, parityMapPath),
      parityMapDigest
    },
    rcWorkflow: {
      name: 'Gate Full1 RC / Release Go-No-Go',
      file: '.github/workflows/gate-full1-rc.yml',
      runId: args.runId,
      runAttempt: args.runAttempt,
      createdAt: evidenceIndex.rcWorkflow && evidenceIndex.rcWorkflow.createdAt
    },
    freshness: {
      evaluatedAt: args.now,
      maxAgeHours: args.maxAgeHours
    },
    requiredMarkers,
    presentMarkers,
    missingMarkers,
    markerSources: derived.markerSources,
    derivedEvidence: derived.derived,
    evidenceSources: sourceEvaluations,
    missingArtifacts: evidenceIndex.missingArtifacts || [],
    invalidArtifacts: evidenceIndex.invalidArtifacts || [],
    errors
  }
  writeSummary(args.jsonOut, summary)

  if (decision !== 'go') {
    console.error(`${failureMarker} ${errors.join('; ')}`)
    process.exit(1)
  }
  console.log(releaseMarker)
}

if (require.main === module) main()

module.exports = {
  deriveMarkers,
  evidenceContracts,
  evaluateSource,
  fullScopeMarkers,
  rolePolicy,
  sha256File
}
