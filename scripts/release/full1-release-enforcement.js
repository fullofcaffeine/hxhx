#!/usr/bin/env node
/**
 * Refuse any >=1.0.0 publication that is not backed by the exact verified RC.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { deriveMarkers, evaluateSource, rolePolicy } = require('../ci/full1-rc-gate')

const releaseMarker = 'FULL1_RELEASE_GO:PASS'
const checklistPath = 'docs/00-project/PUBLIC_1_0_CHECKLIST.md'
const goNoGoPath = 'docs/00-project/FULL1_RELEASE_GO_NO_GO.md'
const scopePath = 'docs/02-user-guide/compat/full-1.0-scope.json'
const parityMapPath = 'docs/00-project/PARITY_MAP_FULL_1_0.json'

function fail(message) {
  console.error(`[full1-release-enforcement] ERROR: ${message}`)
  process.exit(1)
}

function parseVersion(version) {
  const match = /^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-[0-9A-Za-z.-]+)?$/.exec(version)
  if (!match) fail(`invalid semver candidate: ${version}`)
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3])
  }
}

function readJson(filePath, label = filePath) {
  if (!filePath) fail(`missing ${label}`)
  if (!fs.existsSync(filePath)) fail(`missing ${label}: ${filePath}`)
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    fail(`invalid ${label}: ${error.message}`)
  }
}

function sha256File(filePath) {
  return `sha256:${crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')}`
}

function sameArray(left, right) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every((value, index) => value === right[index])
}

function requiredMarkers() {
  const scope = readJson(scopePath)
  const markers = scope && scope.full && scope.full.requiredMarkersPlanned
  if (!Array.isArray(markers) || !markers.includes(releaseMarker)) {
    fail(`${scopePath} must contain the Full1 release marker set`)
  }
  return markers.filter(marker => marker !== releaseMarker)
}

function requireReleaseArtifactIdentity(summary) {
  const verified = process.env.FULL1_RC_ARTIFACT_VERIFIED
  const sourceRunId = Number(process.env.FULL1_RC_SOURCE_RUN_ID)
  const sourceRunAttempt = Number(process.env.FULL1_RC_SOURCE_RUN_ATTEMPT)
  const artifactId = Number(process.env.FULL1_RC_ARTIFACT_ID)
  const artifactDigest = process.env.FULL1_RC_ARTIFACT_DIGEST || ''
  if (verified !== '1') fail('release workflow did not verify the downloaded RC artifact')
  if (!Number.isInteger(sourceRunId) || sourceRunId <= 0) fail('FULL1_RC_SOURCE_RUN_ID is required')
  if (!Number.isInteger(sourceRunAttempt) || sourceRunAttempt <= 0) {
    fail('FULL1_RC_SOURCE_RUN_ATTEMPT is required')
  }
  if (!Number.isInteger(artifactId) || artifactId <= 0) fail('FULL1_RC_ARTIFACT_ID is required')
  if (!/^sha256:[0-9a-f]{64}$/i.test(artifactDigest)) {
    fail('FULL1_RC_ARTIFACT_DIGEST must be a verified SHA-256 digest')
  }
  if (!summary.rcWorkflow
    || summary.rcWorkflow.runId !== sourceRunId
    || summary.rcWorkflow.runAttempt !== sourceRunAttempt) {
    fail('RC summary run identity does not match the downloaded artifact source')
  }
}

/** Recompute the accepted child evidence after the candidate is checked out. */
function validateSources(summary, version, candidateSha, nowMs) {
  if (!Array.isArray(summary.evidenceSources) || summary.evidenceSources.length === 0) {
    fail('RC summary must include evidenceSources[]')
  }
  const maxAgeHours = summary.freshness && Number(summary.freshness.maxAgeHours)
  if (!Number.isFinite(maxAgeHours) || maxAgeHours <= 0) fail('RC freshness.maxAgeHours must be positive')

  const sourceIds = new Set()
  for (const source of summary.evidenceSources) {
    if (!source.id || sourceIds.has(source.id)) fail(`duplicate or missing evidence source id: ${source.id}`)
    sourceIds.add(source.id)
    if (!rolePolicy[source.role]) fail(`unknown evidence source role: ${source.role}`)
    if (source.synthetic !== false) fail(`${source.id}: synthetic evidence is forbidden`)
    if (source.valid !== true || source.accepted !== true) fail(`${source.id}: source was not accepted by the RC evaluator`)
    if (Array.isArray(source.errors) && source.errors.length > 0) fail(`${source.id}: source still has validation errors`)
    if (source.workflowConclusion !== 'success') fail(`${source.id}: source workflow was not successful`)
    if (source.headSha !== candidateSha) fail(`${source.id}: source SHA does not match release checkout`)
    if (source.runId !== summary.rcWorkflow.runId
      || source.runAttempt !== summary.rcWorkflow.runAttempt) {
      fail(`${source.id}: source run/attempt does not match RC workflow`)
    }
    if (!Number.isInteger(source.artifactId) || source.artifactId <= 0) {
      fail(`${source.id}: artifactId must be positive`)
    }
    if (!/^sha256:[0-9a-f]{64}$/i.test(String(source.artifactDigest || ''))) {
      fail(`${source.id}: artifactDigest is invalid`)
    }
    if (!source.createdAt || Number.isNaN(Date.parse(source.createdAt))) {
      fail(`${source.id}: createdAt is invalid`)
    }
    const ageHours = (nowMs - Date.parse(source.createdAt)) / 3600000
    if (ageHours < 0 || ageHours > maxAgeHours) fail(`${source.id}: source artifact is stale or from the future`)
    const policy = rolePolicy[source.role]
    if (source.evidenceTier !== policy.tier) fail(`${source.id}: wrong evidence tier for ${source.role}`)
    if (!Array.isArray(source.markers) || source.markers.length === 0) {
      fail(`${source.id}: markers[] is required`)
    }
    for (const marker of source.markers) {
      if (!policy.markers.includes(marker)) fail(`${source.id}: ${source.role} cannot emit ${marker}`)
    }
    const recomputed = evaluateSource(source, {
      runId: summary.rcWorkflow.runId,
      runAttempt: summary.rcWorkflow.runAttempt,
      candidateSha,
      maxAgeHours
    }, nowMs)
    if (recomputed.errors.length > 0) {
      fail(`${source.id}: release-side source validation failed: ${recomputed.errors.join('; ')}`)
    }
  }

  const derived = deriveMarkers(summary.evidenceSources)
  const required = requiredMarkers()
  const recomputedPresent = required.filter(marker => derived.markers.has(marker))
  if (!sameArray(summary.requiredMarkers, required)) {
    fail('RC summary requiredMarkers[] does not match the current scope manifest')
  }
  if (!sameArray(summary.presentMarkers, recomputedPresent)) {
    fail('RC summary presentMarkers[] does not match recomputed artifact evidence')
  }
  if (recomputedPresent.length !== required.length) fail('recomputed RC evidence is incomplete')
  if (!summary.markerSources || typeof summary.markerSources !== 'object') {
    fail('RC summary markerSources is required')
  }
  for (const marker of required) {
    if (!Array.isArray(summary.markerSources[marker]) || summary.markerSources[marker].length === 0) {
      fail(`RC summary has no source identity for ${marker}`)
    }
  }
  if (JSON.stringify(summary.markerSources) !== JSON.stringify(derived.markerSources)) {
    fail('RC summary markerSources does not match recomputed artifact evidence')
  }
  if (!Array.isArray(summary.derivedEvidence)
    || JSON.stringify(summary.derivedEvidence) !== JSON.stringify(derived.derived)) {
    fail('RC summary derivedEvidence does not match recomputed artifact evidence')
  }
  if (version !== summary.candidate.version) fail('candidate version changed after RC evaluation')
}

/** Apply the final fail-closed checks used by semantic-release. */
function validateSummary(summary, version) {
  if (!summary || typeof summary !== 'object') fail('RC summary must be a JSON object')
  if (summary.schema !== 'full1-rc-summary.v2') {
    fail(`RC summary schema must be full1-rc-summary.v2, received ${summary.schema}`)
  }
  if (summary.evidenceTier !== 10 || summary.synthetic !== false) {
    fail('RC summary must be authentic tier-10 aggregate evidence')
  }
  if (summary.decision !== 'go' || summary.marker !== releaseMarker) {
    fail(`RC summary must record decision=go and marker=${releaseMarker}`)
  }
  if (!summary.candidate || summary.candidate.version !== version) {
    fail(`RC summary candidate version must equal ${version}`)
  }
  if (!summary.rcWorkflow
    || summary.rcWorkflow.name !== 'Gate Full1 RC / Release Go-No-Go'
    || summary.rcWorkflow.file !== '.github/workflows/gate-full1-rc.yml'
    || Number.isNaN(Date.parse(summary.rcWorkflow.createdAt))) {
    fail('RC summary workflow identity is invalid')
  }
  const candidateSha = process.env.FULL1_RELEASE_CANDIDATE_SHA || ''
  if (!/^[0-9a-f]{40}$/i.test(candidateSha)) fail('FULL1_RELEASE_CANDIDATE_SHA is required')
  if (!summary.candidate || summary.candidate.sha !== candidateSha) {
    fail('RC summary candidate SHA does not match the checked-out release candidate')
  }
  if (!summary.contract
    || summary.contract.scopeManifest !== scopePath
    || summary.contract.scopeManifestDigest !== sha256File(scopePath)
    || summary.contract.parityMap !== parityMapPath
    || summary.contract.parityMapDigest !== sha256File(parityMapPath)) {
    fail('RC summary manifest paths/digests do not match the release checkout')
  }
  if (!Array.isArray(summary.missingMarkers) || summary.missingMarkers.length !== 0) {
    fail('RC summary still has missing markers')
  }
  if (!Array.isArray(summary.missingArtifacts) || summary.missingArtifacts.length !== 0) {
    fail('RC summary still has missing artifacts')
  }
  if (!Array.isArray(summary.invalidArtifacts) || summary.invalidArtifacts.length !== 0) {
    fail('RC summary still has invalid artifacts')
  }
  if (!Array.isArray(summary.errors) || summary.errors.length !== 0) {
    fail('RC summary still has evaluator errors')
  }
  if (!summary.freshness || Number.isNaN(Date.parse(summary.freshness.evaluatedAt))) {
    fail('RC summary freshness.evaluatedAt is invalid')
  }
  const nowValue = process.env.FULL1_RELEASE_NOW || new Date().toISOString()
  const nowMs = Date.parse(nowValue)
  if (Number.isNaN(nowMs)) fail('FULL1_RELEASE_NOW must be an ISO timestamp when provided')
  const summaryAgeHours = (nowMs - Date.parse(summary.freshness.evaluatedAt)) / 3600000
  if (summaryAgeHours < 0 || summaryAgeHours > Number(summary.freshness.maxAgeHours)) {
    fail('RC summary is stale or from the future')
  }
  requireReleaseArtifactIdentity(summary)
  validateSources(summary, version, candidateSha, nowMs)
}

function main() {
  const version = process.argv[2]
  if (!version) fail('usage: node scripts/release/full1-release-enforcement.js <nextRelease.version>')

  const parsed = parseVersion(version)
  if (parsed.major < 1) {
    console.log(`FULL1_RELEASE_ENFORCEMENT:SKIP_PRE_1_0 version=${version}`)
    return
  }
  if (process.env.FULL1_RELEASE_GO_MARKER !== releaseMarker) {
    fail(
      [
        `candidate ${version} is >=1.0.0 but FULL1_RELEASE_GO_MARKER is not ${releaseMarker}.`,
        `Use ${goNoGoPath} and ${checklistPath}; do not publish an unlabeled 1.0 claim.`
      ].join(' ')
    )
  }
  const summaryPath = process.env.FULL1_RC_SUMMARY_JSON || ''
  validateSummary(readJson(summaryPath, 'FULL1_RC_SUMMARY_JSON artifact'), version)
  console.log(`FULL1_RELEASE_ENFORCEMENT:PASS version=${version}`)
}

if (require.main === module) main()

module.exports = {
  parseVersion,
  requiredMarkers,
  sha256File,
  validateSummary
}
