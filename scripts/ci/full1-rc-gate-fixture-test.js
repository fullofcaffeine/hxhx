#!/usr/bin/env node
/**
 * Fixture tests for the Full1 RC aggregate evaluator.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')
const scopePath = path.join(root, 'docs/02-user-guide/compat/full-1.0-scope.json')
const scriptPath = path.join(root, 'scripts/ci/full1-rc-gate.js')
const releaseMarker = 'FULL1_RELEASE_GO:PASS'

function fail(message) {
  console.error(`[full1-rc-gate-fixture-test] ${message}`)
  process.exit(1)
}

function evidenceMarkers() {
  const scope = JSON.parse(fs.readFileSync(scopePath, 'utf8'))
  const markers = scope.full && scope.full.requiredMarkersPlanned
  if (!Array.isArray(markers)) fail('scope fixture must define full.requiredMarkersPlanned[]')
  return markers.filter(marker => marker !== releaseMarker)
}

function runCase(name, markers) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), `full1-rc-${name}-`))
  const jsonOut = path.join(dir, 'summary.json')
  const args = [scriptPath, '--json-out', jsonOut]
  for (const marker of markers) args.push('--marker', marker)
  const result = spawnSync(process.execPath, args, {
    cwd: root,
    encoding: 'utf8'
  })
  const summary = fs.existsSync(jsonOut) ? JSON.parse(fs.readFileSync(jsonOut, 'utf8')) : null
  return { result, summary }
}

const allMarkers = evidenceMarkers()
const passCase = runCase('pass', allMarkers)
if (passCase.result.status !== 0) {
  fail(`pass case failed: ${passCase.result.stderr || passCase.result.stdout}`)
}
if (!passCase.result.stdout.includes(releaseMarker)) {
  fail(`pass case did not print ${releaseMarker}`)
}
if (!passCase.summary || passCase.summary.marker !== releaseMarker || passCase.summary.missingMarkers.length !== 0) {
  fail('pass case summary did not record a clean release marker')
}

const missingMarker = 'FULL1_PERF_PARITY:PASS'
const failCase = runCase('missing-perf', allMarkers.filter(marker => marker !== missingMarker))
if (failCase.result.status === 0) {
  fail('missing marker case unexpectedly passed')
}
if (failCase.result.stdout.includes(releaseMarker)) {
  fail(`missing marker case printed ${releaseMarker}`)
}
if (!failCase.summary || failCase.summary.marker !== 'FULL1_RELEASE_GO:FAIL') {
  fail('missing marker case summary did not record failure')
}
if (!failCase.summary.missingMarkers.includes(missingMarker)) {
  fail(`missing marker case summary did not include ${missingMarker}`)
}

const missingFlakeMarker = 'FULL1_FLAKE_POLICY:PASS'
const flakeFailCase = runCase('missing-flake-policy', allMarkers.filter(marker => marker !== missingFlakeMarker))
if (flakeFailCase.result.status === 0) {
  fail('missing flake-policy marker case unexpectedly passed')
}
if (flakeFailCase.result.stdout.includes(releaseMarker)) {
  fail(`missing flake-policy marker case printed ${releaseMarker}`)
}
if (!flakeFailCase.summary || !flakeFailCase.summary.missingMarkers.includes(missingFlakeMarker)) {
  fail(`missing flake-policy marker case did not include ${missingFlakeMarker}`)
}

console.log('[full1-rc-gate-fixture-test] ok')
