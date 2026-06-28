#!/usr/bin/env node
/**
 * Block unlabeled/Full 1.0 release paths without Full1 RC evidence.
 *
 * This script is wired into semantic-release verifyReleaseCmd, where
 * ${nextRelease.version} is available before prepare/publish steps run.
 */

const fs = require('fs')

const releaseMarker = 'FULL1_RELEASE_GO:PASS'
const checklistPath = 'docs/00-project/PUBLIC_1_0_CHECKLIST.md'
const goNoGoPath = 'docs/00-project/FULL1_RELEASE_GO_NO_GO.md'

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

function readSummary(path) {
  if (!path) {
    fail(`candidate >=1.0.0 requires FULL1_RC_SUMMARY_JSON pointing at the RC summary artifact`)
  }
  if (!fs.existsSync(path)) fail(`missing FULL1_RC_SUMMARY_JSON artifact: ${path}`)
  try {
    return JSON.parse(fs.readFileSync(path, 'utf8'))
  } catch (error) {
    fail(`invalid FULL1_RC_SUMMARY_JSON artifact: ${error.message}`)
  }
}

function validateSummary(summary) {
  if (!summary || typeof summary !== 'object') fail('RC summary must be a JSON object')
  if (summary.schema !== 'full1-rc-summary.v1') {
    fail(`RC summary schema must be full1-rc-summary.v1, received ${summary.schema}`)
  }
  if (summary.marker !== releaseMarker) {
    fail(`RC summary marker must be ${releaseMarker}`)
  }
  if (!Array.isArray(summary.requiredMarkers) || summary.requiredMarkers.length === 0) {
    fail('RC summary must include requiredMarkers[]')
  }
  if (!Array.isArray(summary.missingMarkers)) {
    fail('RC summary must include missingMarkers[]')
  }
  if (summary.missingMarkers.length !== 0) {
    fail(`RC summary still has missing markers: ${summary.missingMarkers.join(', ')}`)
  }
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

  validateSummary(readSummary(process.env.FULL1_RC_SUMMARY_JSON || ''))
  console.log(`FULL1_RELEASE_ENFORCEMENT:PASS version=${version}`)
}

main()
