#!/usr/bin/env node
/**
 * Synthetic coverage for Full1 semantic-release enforcement.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')
const script = path.join(root, 'scripts/release/full1-release-enforcement.js')
const marker = 'FULL1_RELEASE_GO:PASS'

function run(version, env = {}) {
  return spawnSync(process.execPath, [script, version], {
    cwd: root,
    env: {
      ...process.env,
      FULL1_RELEASE_GO_MARKER: '',
      FULL1_RC_SUMMARY_JSON: '',
      ...env
    },
    encoding: 'utf8'
  })
}

function assert(condition, message) {
  if (!condition) {
    console.error(`[full1-release-enforcement-fixture-test] ERROR: ${message}`)
    process.exit(1)
  }
}

function writeSummary(dir, body) {
  const summaryPath = path.join(dir, 'full1-rc.summary.json')
  fs.writeFileSync(summaryPath, `${JSON.stringify(body, null, 2)}\n`)
  return summaryPath
}

function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-release-enforcement-'))
  try {
    const pre1 = run('0.16.0')
    assert(pre1.status === 0, `0.x release should pass, got ${pre1.status}: ${pre1.stderr}`)
    assert(pre1.stdout.includes('FULL1_RELEASE_ENFORCEMENT:SKIP_PRE_1_0'), '0.x release should emit skip marker')

    const blocked = run('1.0.0')
    assert(blocked.status !== 0, '1.0.0 without marker must fail')
    assert(blocked.stderr.includes('FULL1_RELEASE_GO_MARKER'), 'missing marker failure should name marker env')

    const missingSummary = run('1.0.0', { FULL1_RELEASE_GO_MARKER: marker })
    assert(missingSummary.status !== 0, '1.0.0 with marker but no summary must fail')
    assert(missingSummary.stderr.includes('FULL1_RC_SUMMARY_JSON'), 'missing summary failure should name summary env')

    const badSummary = writeSummary(temp, {
      schema: 'full1-rc-summary.v1',
      marker,
      requiredMarkers: ['FULL1_SUITE_MATRIX:PASS'],
      missingMarkers: ['FULL1_SUITE_MATRIX:PASS']
    })
    const blockedByMissing = run('1.0.0', {
      FULL1_RELEASE_GO_MARKER: marker,
      FULL1_RC_SUMMARY_JSON: badSummary
    })
    assert(blockedByMissing.status !== 0, '1.0.0 with missing markers in summary must fail')
    assert(blockedByMissing.stderr.includes('missing markers'), 'missing marker summary failure should be explicit')

    const goodSummary = writeSummary(temp, {
      schema: 'full1-rc-summary.v1',
      marker,
      requiredMarkers: ['FULL1_SUITE_MATRIX:PASS'],
      missingMarkers: []
    })
    const allowed = run('1.0.0', {
      FULL1_RELEASE_GO_MARKER: marker,
      FULL1_RC_SUMMARY_JSON: goodSummary
    })
    assert(allowed.status === 0, `1.0.0 with valid RC evidence should pass: ${allowed.stderr}`)
    assert(allowed.stdout.includes('FULL1_RELEASE_ENFORCEMENT:PASS'), 'valid 1.0.0 should emit pass marker')

    const invalidVersion = run('v1.0.0')
    assert(invalidVersion.status !== 0, 'invalid semver should fail')

    console.log('[full1-release-enforcement-fixture-test] ok')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
