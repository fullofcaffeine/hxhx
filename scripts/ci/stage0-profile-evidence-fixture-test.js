#!/usr/bin/env node
/**
 * Exercise Stage0 profile evidence validation and its workflow wiring with
 * small synthetic reports. No compiler build is required for this contract.
 */

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const validator = path.join(root, 'scripts/ci/stage0-profile-evidence-check.js')
const workflowPath = path.join(root, '.github/workflows/stage0-source-smoke.yml')
const requiredClasses = [
  'backend.cpp.CppTargetCore',
  'backend.cpp.CppKnownStdlibSignatures'
]

function fail(message) {
  console.error(`[stage0-profile-evidence-fixture-test] FAIL ${message}`)
  process.exit(1)
}

function validReport() {
  return {
    status: 'ok',
    exit_code: 0,
    phase_seconds: { emit: 190, total: 205 }
  }
}

function validProgress() {
  return {
    schema: 'stage0-progress-summary.v1',
    missing_input: false,
    class_totals: requiredClasses.map((name, index) => ({
      name,
      samples: 1,
      total_dt_ms: index === 0 ? 90000 : 140,
      max_dt_ms: index === 0 ? 90000 : 140,
      min_dt_ms: index === 0 ? 90000 : 140,
      last_count: index + 1
    }))
  }
}

function runCase(tmpDir, name, report, progress, expectedStatus, expectedText = '') {
  const reportPath = path.join(tmpDir, `${name}.report.json`)
  const progressPath = path.join(tmpDir, `${name}.progress.json`)
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
  fs.writeFileSync(progressPath, `${JSON.stringify(progress, null, 2)}\n`)

  const args = [validator, '--report', reportPath, '--progress-summary', progressPath]
  for (const className of requiredClasses) args.push('--require-class', className)
  const result = childProcess.spawnSync(process.execPath, args, { cwd: root, encoding: 'utf8' })

  if (result.status !== expectedStatus) {
    fail(`${name}: expected exit ${expectedStatus}, received ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  const combined = `${result.stdout}\n${result.stderr}`
  if (expectedText && !combined.includes(expectedText)) {
    fail(`${name}: missing diagnostic ${JSON.stringify(expectedText)}\n${combined}`)
  }
}

function checkWorkflow() {
  const workflow = fs.readFileSync(workflowPath, 'utf8')
  const requiredFragments = [
    '--failfast 300',
    'node scripts/ci/stage0-profile-evidence-check.js',
    '--report "$PROFILE_DIR/regen_report.json"',
    '--progress-summary "$PROFILE_DIR/progress_summary.json"',
    '--require-class backend.cpp.CppTargetCore',
    '--require-class backend.cpp.CppKnownStdlibSignatures'
  ]
  for (const fragment of requiredFragments) {
    if (!workflow.includes(fragment)) fail(`workflow is missing required profile contract: ${fragment}`)
  }
  if (workflow.includes('--failfast 65')) fail('workflow still uses the known-too-short 65-second timeout')

  const profileIndex = workflow.indexOf('hxhx:profile:stage0-regen')
  const validationIndex = workflow.indexOf('stage0-profile-evidence-check.js')
  const comparisonIndex = workflow.indexOf('stage0-progress-hotspot-gh-baseline.sh')
  if (!(profileIndex < validationIndex && validationIndex < comparisonIndex)) {
    fail('workflow must profile, validate the complete evidence, and only then compare hotspots')
  }
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-stage0-profile-evidence-'))
  try {
    runCase(tmpDir, 'valid', validReport(), validProgress(), 0, 'PASS')

    const failedReport = validReport()
    failedReport.status = 'error'
    failedReport.exit_code = 1
    runCase(tmpDir, 'failed-report', failedReport, validProgress(), 1, 'instead of "ok"')

    const missingClass = validProgress()
    missingClass.class_totals = missingClass.class_totals.slice(0, 1)
    runCase(tmpDir, 'missing-class', validReport(), missingClass, 1, 'missing required class timing')

    const missingTelemetry = validProgress()
    missingTelemetry.missing_input = true
    runCase(tmpDir, 'missing-telemetry', validReport(), missingTelemetry, 1, 'telemetry input was missing')

    checkWorkflow()
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }

  console.log('[stage0-profile-evidence-fixture-test] PASS')
}

main()
