#!/usr/bin/env node
/**
 * Run Full1 policy guards and write a candidate-bound policy evidence file.
 */

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const guards = [
  ['FULL1_TARGET_SCOPE_CONTRACT:PASS', 'scripts/ci/full1-target-scope-check.js'],
  ['FULL1_PARITY_MAP:PASS', 'scripts/ci/full1-parity-map-check.js'],
  ['FULL1_MACRO_EVAL_CONTRACT:PASS', 'scripts/ci/full1-macro-eval-contract-check.js'],
  ['FULL1_PLUGIN_PARITY_CONTRACT:PASS', 'scripts/ci/full1-plugin-parity-contract-check.js'],
  ['FULL1_FLAKE_POLICY:PASS', 'scripts/ci/full1-flake-policy-check.js'],
  ['FULL1_PERF_POLICY:PASS', 'scripts/ci/full1-perf-policy-check.js']
]

function fail(message) {
  console.error(`[full1-rc-policy-evidence] ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const args = { candidateSha: '', candidateVersion: '', runId: 0, runAttempt: 0, jsonOut: '' }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--candidate-sha') args.candidateSha = argv[++i] || ''
    else if (arg === '--candidate-version') args.candidateVersion = argv[++i] || ''
    else if (arg === '--run-id') args.runId = Number(argv[++i])
    else if (arg === '--run-attempt') args.runAttempt = Number(argv[++i])
    else if (arg === '--json-out') args.jsonOut = argv[++i] || ''
    else fail(`unknown argument: ${arg}`)
  }
  if (!/^[0-9a-f]{40}$/i.test(args.candidateSha)) fail('--candidate-sha must be a full SHA')
  if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(args.candidateVersion)) {
    fail('--candidate-version must be semver')
  }
  if (!Number.isInteger(args.runId) || args.runId <= 0) fail('--run-id must be positive')
  if (!Number.isInteger(args.runAttempt) || args.runAttempt <= 0) fail('--run-attempt must be positive')
  if (!args.jsonOut) fail('--json-out is required')
  return args
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const results = []
  const markers = []
  for (const [marker, script] of guards) {
    const result = spawnSync(process.execPath, [script], {
      cwd: process.cwd(),
      encoding: 'utf8'
    })
    const markerObserved = result.status === 0 && result.stdout.includes(marker)
    if (markerObserved) markers.push(marker)
    results.push({
      marker,
      script,
      exitCode: result.status == null ? -1 : result.status,
      markerObserved,
      stdout: result.stdout,
      stderr: result.stderr
    })
  }
  const summary = {
    schema: 'full1-rc-policy-evidence.v1',
    synthetic: false,
    candidate: {
      sha: args.candidateSha,
      version: args.candidateVersion
    },
    run: {
      id: args.runId,
      attempt: args.runAttempt
    },
    createdAt: new Date().toISOString(),
    markers,
    results
  }
  const output = path.resolve(args.jsonOut)
  fs.mkdirSync(path.dirname(output), { recursive: true })
  fs.writeFileSync(output, `${JSON.stringify(summary, null, 2)}\n`)

  const failed = results.filter(result => !result.markerObserved)
  if (failed.length > 0) {
    for (const result of failed) {
      console.error(`${result.marker}: guard failed or did not emit its marker`)
      if (result.stderr) console.error(result.stderr)
    }
    process.exit(1)
  }
  for (const marker of markers) console.log(marker)
}

if (require.main === module) main()

module.exports = { guards, parseArgs }
