#!/usr/bin/env node
/**
 * Validate one complete Stage0 regeneration profile before it is compared or
 * published as performance evidence.
 *
 * The profiler intentionally retains reports after a failed compiler run so a
 * developer can diagnose the failure. This checker keeps those useful partial
 * artifacts from being mistaken for a successful timing sample.
 */

const fs = require('fs')

function usage() {
  console.log(`Usage: node scripts/ci/stage0-profile-evidence-check.js [options]

Options:
  --report <path>            Regeneration report JSON
  --progress-summary <path> Progress summary JSON
  --require-class <name>    Required class timing entry; may be repeated
  -h, --help                Show this help
`)
}

function fail(message) {
  throw new Error(message)
}

function readJson(filePath, label) {
  if (!filePath) fail(`missing ${label} path`)
  if (!fs.existsSync(filePath)) fail(`${label} does not exist: ${filePath}`)

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    fail(`${label} is not valid JSON: ${filePath} (${error.message})`)
  }
}

function validateEvidence(report, progress, requiredClasses) {
  if (report.status !== 'ok') {
    fail(`regeneration status is ${JSON.stringify(report.status)} instead of "ok"`)
  }
  if (report.exit_code !== 0) {
    fail(`regeneration exit_code is ${JSON.stringify(report.exit_code)} instead of 0`)
  }
  if (!report.phase_seconds || !Number.isFinite(report.phase_seconds.total) || report.phase_seconds.total <= 0) {
    fail('regeneration report is missing a positive phase_seconds.total')
  }

  if (progress.schema !== 'stage0-progress-summary.v1') {
    fail(`progress summary schema is ${JSON.stringify(progress.schema)} instead of "stage0-progress-summary.v1"`)
  }
  if (progress.missing_input === true) {
    fail('progress summary says its telemetry input was missing')
  }
  if (!Array.isArray(progress.class_totals)) {
    fail('progress summary class_totals must be an array')
  }

  const classes = new Map(progress.class_totals.map((row) => [row?.name, row]))
  for (const className of requiredClasses) {
    const row = classes.get(className)
    if (!row) fail(`progress summary is missing required class timing: ${className}`)
    if (!Number.isInteger(row.samples) || row.samples <= 0) {
      fail(`required class ${className} has no timing samples`)
    }
    if (!Number.isFinite(row.total_dt_ms) || row.total_dt_ms < 0) {
      fail(`required class ${className} has an invalid total_dt_ms`)
    }
  }
}

function parseArgs(args) {
  const options = {
    reportPath: '',
    progressPath: '',
    requiredClasses: []
  }

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]
    if (arg === '--report') {
      options.reportPath = args[++index] || ''
    } else if (arg === '--progress-summary') {
      options.progressPath = args[++index] || ''
    } else if (arg === '--require-class') {
      const className = args[++index] || ''
      if (!className) fail('--require-class needs a non-empty class name')
      options.requiredClasses.push(className)
    } else if (arg === '--help' || arg === '-h') {
      usage()
      process.exit(0)
    } else {
      fail(`unknown option: ${arg}`)
    }
  }
  return options
}

function main() {
  try {
    const options = parseArgs(process.argv.slice(2))
    const report = readJson(options.reportPath, 'regeneration report')
    const progress = readJson(options.progressPath, 'progress summary')
    validateEvidence(report, progress, options.requiredClasses)
    const classSummary = options.requiredClasses.length > 0 ? options.requiredClasses.join(',') : 'none'
    console.log(`[stage0-profile-evidence-check] PASS required_classes=${classSummary}`)
  } catch (error) {
    console.error(`[stage0-profile-evidence-check] FAIL ${error.message}`)
    process.exit(1)
  }
}

if (require.main === module) main()

module.exports = { validateEvidence }
