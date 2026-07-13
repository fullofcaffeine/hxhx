#!/usr/bin/env node
/**
 * Guard the prepublication, same-candidate Full1 release evidence contract.
 */

const fs = require('fs')

const docPath = 'docs/00-project/FULL1_RELEASE_GO_NO_GO.md'
const publicChecklistPath = 'docs/00-project/PUBLIC_1_0_CHECKLIST.md'
const fullContractPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const ciGatesPath = 'docs/00-project/CI_GATES.md'
const scopeManifestPath = 'docs/02-user-guide/compat/full-1.0-scope.json'
const rcWorkflowPath = '.github/workflows/gate-full1-rc.yml'
const releaseWorkflowPath = '.github/workflows/release.yml'
const rcCollectorPath = 'scripts/ci/full1-rc-artifact-collector.js'
const rcEvaluatorPath = 'scripts/ci/full1-rc-gate.js'
const rcDownloadPath = 'scripts/release/download-full1-rc-artifact.js'
const releaseEnforcementPath = 'scripts/release/full1-release-enforcement.js'
const packageJsonPath = 'package.json'
const releaseMarker = 'FULL1_RELEASE_GO:PASS'

const requiredDocSnippets = [
  'Full1 Release Go/No-Go',
  'Scoped profile',
  'Full 1.0',
  scopeManifestPath,
  publicChecklistPath,
  rcWorkflowPath,
  rcCollectorPath,
  rcEvaluatorPath,
  rcDownloadPath,
  'full1-rc-summary.v2',
  'candidate SHA',
  'run attempt',
  'artifact digest',
  'prepublication',
  'missingMarkers',
  'requiredMarkers',
  releaseMarker,
  'No-go decision',
  releaseEnforcementPath
]

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function readUtf8(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`missing required file: ${filePath}`)
    return ''
  }
  return fs.readFileSync(filePath, 'utf8')
}

function readJson(filePath) {
  const text = readUtf8(filePath)
  if (!text) return null
  try {
    return JSON.parse(text)
  } catch (error) {
    fail(`invalid JSON in ${filePath}: ${error.message}`)
    return null
  }
}

function requireIncludes(filePath, text, snippet) {
  if (!text.includes(snippet)) fail(`${filePath} must include: ${snippet}`)
}

function requireExcludes(filePath, text, snippet) {
  if (text.includes(snippet)) fail(`${filePath} must not include: ${snippet}`)
}

function main() {
  const doc = readUtf8(docPath)
  const checklist = readUtf8(publicChecklistPath)
  const fullContract = readUtf8(fullContractPath)
  const ciGates = readUtf8(ciGatesPath)
  const scope = readJson(scopeManifestPath)
  const rcWorkflow = readUtf8(rcWorkflowPath)
  const releaseWorkflow = readUtf8(releaseWorkflowPath)
  const rcCollector = readUtf8(rcCollectorPath)
  const rcEvaluator = readUtf8(rcEvaluatorPath)
  const rcDownload = readUtf8(rcDownloadPath)
  const releaseEnforcement = readUtf8(releaseEnforcementPath)
  const packageJson = readUtf8(packageJsonPath)

  for (const snippet of requiredDocSnippets) requireIncludes(docPath, doc, snippet)

  requireIncludes(publicChecklistPath, checklist, '## Scoped 1.0')
  requireIncludes(publicChecklistPath, checklist, '## Full 1.0')
  requireIncludes(publicChecklistPath, checklist, releaseMarker)
  requireIncludes(publicChecklistPath, checklist, docPath)
  requireIncludes(fullContractPath, fullContract, docPath)
  requireIncludes(ciGatesPath, ciGates, docPath)
  requireIncludes(ciGatesPath, ciGates, releaseMarker)
  requireIncludes(ciGatesPath, ciGates, 'prepublication')

  if (scope) {
    const planned = scope.full && scope.full.requiredMarkersPlanned
    if (!Array.isArray(planned)) {
      fail(`${scopeManifestPath} must define full.requiredMarkersPlanned[]`)
    } else if (!planned.includes(releaseMarker)) {
      fail(`${scopeManifestPath} must include ${releaseMarker}`)
    }
  }

  for (const snippet of [
    'candidate_version:',
    'provenance_only:',
    'actions: read',
    rcCollectorPath,
    rcEvaluatorPath,
    'full1-rc.evidence-index.json',
    'full1-rc.summary.json',
    'full1-rc-summary-${{ github.run_id }}-${{ github.run_attempt }}'
  ]) {
    requireIncludes(rcWorkflowPath, rcWorkflow, snippet)
  }
  requireExcludes(rcWorkflowPath, rcWorkflow, 'types: [published]')
  requireExcludes(rcWorkflowPath, rcWorkflow, 'workflow_call:')

  for (const snippet of [
    'full1-rc-evidence-index.v1',
    'artifactDigest',
    'artifactId',
    'runAttempt',
    'evidenceTier',
    'synthetic: false'
  ]) {
    requireIncludes(rcCollectorPath, rcCollector, snippet)
  }

  for (const snippet of [
    scopeManifestPath,
    'full1-rc-summary.v2',
    'evidenceContracts',
    'evidenceSources',
    'requiredMarkers',
    'missingMarkers',
    releaseMarker
  ]) {
    requireIncludes(rcEvaluatorPath, rcEvaluator, snippet)
  }
  requireExcludes(rcEvaluatorPath, rcEvaluator, "arg === '--marker'")

  for (const snippet of [
    'full1_rc_run_id:',
    'full1_rc_run_attempt:',
    'provenance_dry_run:',
    rcDownloadPath,
    'Checkout the exact release candidate',
    'FULL1_RC_ARTIFACT_VERIFIED',
    'FULL1_RELEASE_HANDOFF_DRY_RUN:NO_GO_EXPECTED',
    'if: ${{ !inputs.provenance_dry_run }}',
    'npx semantic-release'
  ]) {
    requireIncludes(releaseWorkflowPath, releaseWorkflow, snippet)
  }

  for (const snippet of [
    'full1-rc-release-handoff.v1',
    'full1-rc-summary-${args.runId}-${args.runAttempt}',
    'downloaded RC artifact ZIP digest',
    'validateHandoff'
  ]) {
    requireIncludes(rcDownloadPath, rcDownload, snippet)
  }

  for (const snippet of [
    releaseMarker,
    'FULL1_RELEASE_GO_MARKER',
    'FULL1_RC_SUMMARY_JSON',
    'FULL1_RC_ARTIFACT_VERIFIED',
    'full1-rc-summary.v2',
    'FULL1_RELEASE_ENFORCEMENT:PASS'
  ]) {
    requireIncludes(releaseEnforcementPath, releaseEnforcement, snippet)
  }

  const attemptBoundArtifacts = [
    ['.github/workflows/gate3-full1-extended.yml', 'full1-gate3-extended-${{ github.run_id }}-${{ github.run_attempt }}'],
    ['.github/workflows/full1-suite-runners.yml', 'full1-suite-${{ matrix.suite }}-${{ github.run_id }}-${{ github.run_attempt }}'],
    ['.github/workflows/macro-runtime-parity-weekly.yml', 'macro-runtime-parity-summary-${{ github.run_id }}-${{ github.run_attempt }}'],
    ['.github/workflows/full1-eval-native.yml', 'full1-eval-native-${{ github.run_id }}-${{ github.run_attempt }}'],
    ['.github/workflows/full1-plugin-parity.yml', 'full1-plugin-parity-summary-${{ github.run_id }}-${{ github.run_attempt }}'],
    ['.github/workflows/gate-perf-full1.yml', 'full1-perf-evaluated-${{ github.run_id }}-${{ github.run_attempt }}']
  ]
  for (const [filePath, snippet] of attemptBoundArtifacts) {
    requireIncludes(filePath, readUtf8(filePath), snippet)
  }

  for (const snippet of [
    'verifyReleaseCmd',
    releaseEnforcementPath,
    'test:full1:rc-artifact-collector',
    'test:full1:rc-release-handoff'
  ]) {
    requireIncludes(packageJsonPath, packageJson, snippet)
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full1 prepublication release evidence contract is valid')
}

main()
