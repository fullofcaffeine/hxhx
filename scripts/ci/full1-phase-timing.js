#!/usr/bin/env node

/**
 * Records and validates report-only phase timings from heavy Full1 workflows.
 *
 * A downloaded summary must explain which code, GitHub run, machine, and
 * toolchain produced it. Phase totals deliberately cover only the measured
 * commands; setup gaps and other uninstrumented job time are not implied.
 */

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const {
  isIsoTimestamp,
  isNormalizedPath,
  isSha,
  nonEmptyString,
  parseBoolean,
  readJson,
  runTool
} = require('./benchmark-report-common.js')

const recordSchema = 'full1-phase-timing-record.v2'
const summarySchema = 'full1-phase-timing-summary.v2'
const passMarker = 'FULL1_PHASE_TIMING_REPORT:PASS'
const evidenceLevel = 'diagnostic-report-only'
const thresholdPolicy = 'report-only; no blocking threshold'
const measurementSource = 'scripts/ci/full1-phase-timing.js'
const measuredTimeScope = 'sum of recorded phase durations; not total GitHub job wall time'
const repoRoot = path.resolve(__dirname, '../..')

function fail(message) {
  console.error(`[full1-phase-timing] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const args = { command: argv[0] || '' }
  for (let index = 1; index < argv.length; index += 1) {
    const key = argv[index]
    if (!key.startsWith('--')) throw new Error(`unexpected positional argument: ${key}`)
    const value = argv[index + 1]
    if (value == null || value.startsWith('--')) throw new Error(`missing value for ${key}`)
    args[key.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value
    index += 1
  }
  return args
}

function requireArg(args, key) {
  if (!nonEmptyString(args[key])) {
    throw new Error(`missing --${key.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`)}`)
  }
  return args[key]
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true })
}

function parseNonNegativeInteger(value, label) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed < 0) throw new Error(`${label} must be an integer >= 0`)
  return parsed
}

function parsePositiveInteger(value, label) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed < 1) throw new Error(`${label} must be an integer >= 1`)
  return parsed
}

function readRecords(jsonlPath) {
  if (!fs.existsSync(jsonlPath)) return []
  return fs.readFileSync(jsonlPath, 'utf8')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line)
      } catch (error) {
        throw new Error(`${jsonlPath} line ${index + 1} is not valid JSON: ${error.message}`)
      }
    })
}

function gitOutput(args) {
  const result = childProcess.spawnSync('git', args, {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== 0) {
    throw new Error(`git ${args.join(' ')} failed: ${(result.stderr || result.stdout || '').trim()}`)
  }
  return (result.stdout || '').trim()
}

function resolveCommit(args) {
  const checkoutCommit = gitOutput(['rev-parse', 'HEAD']).toLowerCase()
  const commit = args.commit || process.env.GITHUB_SHA || checkoutCommit
  if (!isSha(commit)) throw new Error('commit must be a 40-character Git SHA')
  const normalized = commit.toLowerCase()
  if (!args.commit && process.env.GITHUB_SHA && normalized !== checkoutCommit) {
    throw new Error(`GitHub candidate ${normalized} does not match checked-out commit ${checkoutCommit}`)
  }
  return normalized
}

function resolveTrackedSourceClean(args) {
  if (args.trackedSourceClean != null) {
    return parseBoolean(args.trackedSourceClean, '--tracked-source-clean')
  }
  return gitOutput(['status', '--porcelain', '--untracked-files=no']) === ''
}

function resolveRunIdentity(args) {
  const runId = args.runId || process.env.GITHUB_RUN_ID || 'local'
  const runAttempt = args.runAttempt || process.env.GITHUB_RUN_ATTEMPT || 'local'
  if (runId === 'local' || runAttempt === 'local') {
    if (runId !== 'local' || runAttempt !== 'local') {
      throw new Error('local phase timing must use local for both run ID and attempt')
    }
    return { run_id: 'local', run_attempt: 'local' }
  }
  return {
    run_id: String(parsePositiveInteger(runId, 'GitHub run ID')),
    run_attempt: String(parsePositiveInteger(runAttempt, 'GitHub run attempt'))
  }
}

function optionalToolVersion(args, key, command, commandArgs, label) {
  if (nonEmptyString(args[key])) return args[key].trim()
  try {
    return runTool(command, commandArgs, label, repoRoot)
  } catch (_) {
    return 'unavailable'
  }
}

function normalizedEvidencePath(filePath) {
  const absolute = path.resolve(filePath)
  const relative = path.relative(repoRoot, absolute)
  if (relative && !relative.startsWith('..') && !path.isAbsolute(relative)) {
    return relative.split(path.sep).join('/')
  }
  return path.basename(absolute)
}

function buildEnvironment(args) {
  return {
    os: args.os || os.type(),
    architecture: args.architecture || os.arch(),
    cpu_model: args.cpuModel || os.cpus()[0]?.model || 'unavailable',
    node_version: args.nodeVersion || process.version,
    haxe_version: optionalToolVersion(args, 'haxeVersion', 'haxe', ['--version'], 'Haxe version'),
    python_version: optionalToolVersion(args, 'pythonVersion', 'python3', ['--version'], 'Python version'),
    ocamlc_version: optionalToolVersion(args, 'ocamlcVersion', 'ocamlc', ['-version'], 'OCaml bytecode compiler version'),
    ocamlopt_version: optionalToolVersion(args, 'ocamloptVersion', 'ocamlopt', ['-version'], 'OCaml native compiler version'),
    dune_version: optionalToolVersion(args, 'duneVersion', 'dune', ['--version'], 'Dune version')
  }
}

function buildCiIdentity(args, records) {
  const run = resolveRunIdentity(args)
  const local = run.run_id === 'local'
  const commit = resolveCommit(args)
  const workflowSha = args.workflowSha || process.env.GITHUB_WORKFLOW_SHA || (local ? 'unavailable' : commit)
  return {
    provider: local ? 'local' : 'github-actions',
    repository: args.repository || process.env.GITHUB_REPOSITORY || 'local',
    event_name: args.eventName || process.env.GITHUB_EVENT_NAME || 'local',
    workflow_name: args.workflowName || process.env.GITHUB_WORKFLOW || records[0].workflow,
    workflow_ref: args.workflowRef || process.env.GITHUB_WORKFLOW_REF || 'unavailable',
    workflow_sha: workflowSha,
    job_id: args.jobId || process.env.GITHUB_JOB || records[0].job,
    runner_name: args.runnerName || process.env.RUNNER_NAME || 'local',
    ...run
  }
}

function appendRecord(args) {
  const startedMs = Number(requireArg(args, 'startedMs'))
  const endedMs = Number(requireArg(args, 'endedMs'))
  const exitCode = parseNonNegativeInteger(requireArg(args, 'exitCode'), 'exit code')
  if (!Number.isFinite(startedMs) || !Number.isFinite(endedMs)) {
    throw new Error('started/ended timestamps must be numeric milliseconds')
  }
  if (endedMs < startedMs) throw new Error('ended timestamp must not precede started timestamp')
  const status = requireArg(args, 'status')
  if (!['pass', 'fail'].includes(status)) throw new Error('status must be pass or fail')
  if ((status === 'pass') !== (exitCode === 0)) {
    throw new Error('pass requires exit code 0 and fail requires a non-zero exit code')
  }
  const run = resolveRunIdentity(args)
  const record = {
    schema: recordSchema,
    git_commit: resolveCommit(args),
    ...run,
    workflow: requireArg(args, 'workflow'),
    job: requireArg(args, 'job'),
    phase: requireArg(args, 'phase'),
    status,
    exit_code: exitCode,
    started_at: new Date(startedMs).toISOString(),
    ended_at: new Date(endedMs).toISOString(),
    duration_ms: Math.max(0, endedMs - startedMs)
  }
  if (args.detail) record.detail = args.detail
  const errors = validateRecord(record, 'phase record')
  if (errors.length > 0) throw new Error(errors.join('\n'))
  const jsonl = requireArg(args, 'jsonl')
  ensureParent(jsonl)
  fs.appendFileSync(jsonl, `${JSON.stringify(record)}\n`, 'utf8')
  console.log(`[full1-phase-timing] phase=${record.phase} status=${record.status} duration_ms=${record.duration_ms}`)
}

function absoluteStringLocations(value, owner = 'report', output = []) {
  if (typeof value === 'string') {
    if (path.isAbsolute(value) || /^[A-Za-z]:[\\/]/.test(value) || value.startsWith('~/')) output.push(owner)
    return output
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => absoluteStringLocations(item, `${owner}[${index}]`, output))
    return output
  }
  if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) absoluteStringLocations(item, `${owner}.${key}`, output)
  }
  return output
}

function validateRunIdentity(runId, runAttempt, owner, errors) {
  if (runId === 'local' || runAttempt === 'local') {
    if (runId !== 'local' || runAttempt !== 'local') errors.push(`${owner} must use local for both run ID and attempt`)
    return
  }
  if (!/^\d+$/.test(runId || '') || Number(runId) < 1) errors.push(`${owner}.run_id must be a positive integer string or local`)
  if (!/^\d+$/.test(runAttempt || '') || Number(runAttempt) < 1) errors.push(`${owner}.run_attempt must be a positive integer string or local`)
}

function validateRecord(record, owner) {
  const errors = []
  if (record?.schema !== recordSchema) errors.push(`${owner}.schema must be ${recordSchema}`)
  if (!isSha(record?.git_commit)) errors.push(`${owner}.git_commit must be a 40-character SHA`)
  validateRunIdentity(record?.run_id, record?.run_attempt, owner, errors)
  for (const key of ['workflow', 'job', 'phase']) {
    if (!nonEmptyString(record?.[key])) errors.push(`${owner}.${key} is required`)
  }
  if (!['pass', 'fail'].includes(record?.status)) errors.push(`${owner}.status must be pass or fail`)
  if (!Number.isInteger(record?.exit_code) || record.exit_code < 0) errors.push(`${owner}.exit_code must be an integer >= 0`)
  if (record?.status === 'pass' && record?.exit_code !== 0) errors.push(`${owner} pass status requires exit code 0`)
  if (record?.status === 'fail' && record?.exit_code === 0) errors.push(`${owner} fail status requires a non-zero exit code`)
  if (!isIsoTimestamp(record?.started_at)) errors.push(`${owner}.started_at must be a canonical ISO timestamp`)
  if (!isIsoTimestamp(record?.ended_at)) errors.push(`${owner}.ended_at must be a canonical ISO timestamp`)
  if (!Number.isInteger(record?.duration_ms) || record.duration_ms < 0) errors.push(`${owner}.duration_ms must be an integer >= 0`)
  if (isIsoTimestamp(record?.started_at) && isIsoTimestamp(record?.ended_at)) {
    const expected = Date.parse(record.ended_at) - Date.parse(record.started_at)
    if (expected < 0) errors.push(`${owner}.ended_at must not precede started_at`)
    if (record.duration_ms !== expected) errors.push(`${owner}.duration_ms does not match timestamps`)
  }
  if (record?.detail != null && !nonEmptyString(record.detail)) errors.push(`${owner}.detail must be a non-empty string when present`)
  return errors
}

function buildSummary(args) {
  const jsonl = requireArg(args, 'jsonl')
  const records = readRecords(jsonl)
  if (records.length === 0) throw new Error(`no timing records found in ${jsonl}`)
  const recordErrors = records.flatMap((record, index) => validateRecord(record, `phases[${index}]`))
  if (recordErrors.length > 0) throw new Error(recordErrors.join('\n'))
  const commit = resolveCommit(args)
  const run = resolveRunIdentity(args)
  const workflow = records[0].workflow
  const job = records[0].job
  for (const [index, record] of records.entries()) {
    if (record.git_commit !== commit) throw new Error(`phases[${index}] commit does not match ${commit}`)
    if (record.run_id !== run.run_id || record.run_attempt !== run.run_attempt) {
      throw new Error(`phases[${index}] GitHub run identity does not match the summary`)
    }
    if (record.workflow !== workflow || record.job !== job) {
      throw new Error(`phases[${index}] workflow/job does not match the first phase`)
    }
  }
  const totalDurationMs = records.reduce((sum, record) => sum + record.duration_ms, 0)
  const failed = records.filter(record => record.status !== 'pass' || record.exit_code !== 0)
  return {
    schema: summarySchema,
    evidence_level: evidenceLevel,
    marker: passMarker,
    recorded_at: args.recordedAt || new Date().toISOString(),
    git: {
      commit,
      tracked_source_clean_at_summary: resolveTrackedSourceClean(args)
    },
    ci: buildCiIdentity(args, records),
    environment: buildEnvironment(args),
    workflow,
    job,
    measurement: {
      source: measurementSource,
      phase_source: normalizedEvidencePath(jsonl),
      measured_time_scope: measuredTimeScope,
      threshold_policy: thresholdPolicy
    },
    phase_count: records.length,
    total_measured_phase_duration_ms: totalDurationMs,
    failed_phase_count: failed.length,
    phases: records
  }
}

function validateSummary(report, expectedCommit = null) {
  const errors = []
  if (report?.schema !== summarySchema) errors.push(`schema must be ${summarySchema}`)
  if (report?.evidence_level !== evidenceLevel) errors.push(`evidence_level must be ${evidenceLevel}`)
  if (report?.marker !== passMarker) errors.push(`marker must be ${passMarker}`)
  if (!isIsoTimestamp(report?.recorded_at)) errors.push('recorded_at must be a canonical ISO timestamp')
  if (!isSha(report?.git?.commit)) errors.push('git.commit must be a 40-character SHA')
  if (expectedCommit && report?.git?.commit !== expectedCommit) errors.push(`git.commit does not match expected commit ${expectedCommit}`)
  if (typeof report?.git?.tracked_source_clean_at_summary !== 'boolean') {
    errors.push('git.tracked_source_clean_at_summary must be boolean')
  }
  for (const key of ['workflow', 'job']) {
    if (!nonEmptyString(report?.[key])) errors.push(`${key} is required`)
  }
  const ci = report?.ci || {}
  if (!['local', 'github-actions'].includes(ci.provider)) errors.push('ci.provider must be local or github-actions')
  for (const key of ['repository', 'event_name', 'workflow_name', 'workflow_ref', 'workflow_sha', 'job_id', 'runner_name']) {
    if (!nonEmptyString(ci[key])) errors.push(`ci.${key} is required`)
  }
  if (ci.workflow_sha !== 'unavailable' && !isSha(ci.workflow_sha)) {
    errors.push('ci.workflow_sha must be a 40-character SHA or unavailable')
  }
  validateRunIdentity(ci.run_id, ci.run_attempt, 'ci', errors)
  if (ci.provider === 'local' && ci.run_id !== 'local') errors.push('local reports must use a local run identity')
  if (ci.provider === 'github-actions' && ci.run_id === 'local') errors.push('GitHub reports must use a numeric run identity')
  const environment = report?.environment || {}
  for (const key of ['os', 'architecture', 'cpu_model', 'node_version', 'haxe_version', 'python_version', 'ocamlc_version', 'ocamlopt_version', 'dune_version']) {
    if (!nonEmptyString(environment[key])) errors.push(`environment.${key} is required; use unavailable when needed`)
  }
  const measurement = report?.measurement || {}
  if (measurement.source !== measurementSource) errors.push(`measurement.source must be ${measurementSource}`)
  if (!isNormalizedPath(measurement.phase_source)) errors.push('measurement.phase_source must be a normalized repository-safe path')
  if (measurement.measured_time_scope !== measuredTimeScope) errors.push('measurement.measured_time_scope does not explain the phase-only total')
  if (measurement.threshold_policy !== thresholdPolicy) errors.push(`measurement.threshold_policy must be ${thresholdPolicy}`)
  if (!Number.isInteger(report?.phase_count) || report.phase_count < 1) errors.push('phase_count must be an integer >= 1')
  if (!Number.isInteger(report?.total_measured_phase_duration_ms) || report.total_measured_phase_duration_ms < 0) {
    errors.push('total_measured_phase_duration_ms must be an integer >= 0')
  }
  if (!Number.isInteger(report?.failed_phase_count) || report.failed_phase_count < 0) {
    errors.push('failed_phase_count must be an integer >= 0')
  }
  if (!Array.isArray(report?.phases) || report.phases.length === 0) {
    errors.push('phases must be a non-empty array')
  } else {
    errors.push(...report.phases.flatMap((record, index) => validateRecord(record, `phases[${index}]`)))
    if (report.phase_count !== report.phases.length) errors.push('phase_count does not match phases length')
    const total = report.phases.reduce((sum, record) => sum + Number(record.duration_ms || 0), 0)
    if (report.total_measured_phase_duration_ms !== total) errors.push('total measured duration does not match raw phases')
    const failed = report.phases.filter(record => record.status !== 'pass' || record.exit_code !== 0).length
    if (report.failed_phase_count !== failed) errors.push('failed_phase_count does not match raw phases')
    for (const [index, record] of report.phases.entries()) {
      if (record.git_commit !== report.git?.commit) errors.push(`phases[${index}] commit does not match summary`)
      if (record.workflow !== report.workflow || record.job !== report.job) errors.push(`phases[${index}] workflow/job does not match summary`)
      if (record.run_id !== ci.run_id || record.run_attempt !== ci.run_attempt) {
        errors.push(`phases[${index}] run identity does not match summary`)
      }
    }
  }
  for (const location of absoluteStringLocations(report)) errors.push(`${location} contains an absolute machine-local path`)
  return errors
}

function markdown(report) {
  const runLabel = report.ci.provider === 'github-actions'
    ? `${report.ci.run_id} attempt ${report.ci.run_attempt} on ${report.ci.runner_name}`
    : 'local run'
  const lines = [
    `### Full1 phase timings: ${report.job}`,
    '',
    `- Commit: \`${report.git.commit}\``,
    `- Run: \`${runLabel}\``,
    `- Machine: \`${report.environment.os} ${report.environment.architecture}\` — \`${report.environment.cpu_model}\``,
    `- Toolchains: Node \`${report.environment.node_version}\`, Haxe \`${report.environment.haxe_version}\`, OCaml native \`${report.environment.ocamlopt_version}\`, Dune \`${report.environment.dune_version}\``,
    `- Tracked source clean when summarized: \`${report.git.tracked_source_clean_at_summary}\``,
    '- Evidence: `diagnostic / report-only`',
    '- Total meaning: recorded phases only; this is not necessarily the whole GitHub job wall time.',
    '',
    '| Phase | Status | Exit | Duration (s) |',
    '| --- | --- | ---: | ---: |'
  ]
  for (const record of report.phases) {
    lines.push(`| ${record.phase} | ${record.status} | ${record.exit_code} | ${(record.duration_ms / 1000).toFixed(3)} |`)
  }
  lines.push('')
  lines.push(`Total measured phase time: ${(report.total_measured_phase_duration_ms / 1000).toFixed(3)}s`)
  lines.push(`Failed measured phases: ${report.failed_phase_count}`)
  lines.push('')
  return lines.join('\n')
}

function summarize(args) {
  const report = buildSummary(args)
  const errors = validateSummary(report, resolveCommit(args))
  if (errors.length > 0) throw new Error(errors.join('\n'))
  const jsonOut = requireArg(args, 'jsonOut')
  const markdownOut = requireArg(args, 'markdownOut')
  ensureParent(jsonOut)
  ensureParent(markdownOut)
  fs.writeFileSync(jsonOut, `${JSON.stringify(report, null, 2)}\n`, 'utf8')
  fs.writeFileSync(markdownOut, `${markdown(report)}\n`, 'utf8')
  console.log(`[full1-phase-timing] summary=${jsonOut}`)
}

function main(argv) {
  try {
    const args = parseArgs(argv)
    if (args.command === 'append') {
      appendRecord(args)
      return
    }
    if (args.command === 'summarize') {
      summarize(args)
      return
    }
    if (args.command === 'validate') {
      const report = readJson(requireArg(args, 'report'), 'Full1 phase timing report')
      const expectedCommit = args.expectedCommit || null
      if (expectedCommit && !isSha(expectedCommit)) throw new Error('--expected-commit must be a 40-character SHA')
      const errors = validateSummary(report, expectedCommit)
      if (errors.length > 0) throw new Error(errors.join('\n'))
      console.log(passMarker)
      console.log('[ci:guards] OK: Full1 phase timing report is self-describing')
      return
    }
    if (args.command === 'markdown') {
      const report = readJson(requireArg(args, 'report'), 'Full1 phase timing report')
      const errors = validateSummary(report)
      if (errors.length > 0) throw new Error(errors.join('\n'))
      process.stdout.write(markdown(report))
      return
    }
    throw new Error('usage: full1-phase-timing.js <append|summarize|validate|markdown> [options]')
  } catch (error) {
    fail(error.message)
  }
}

if (require.main === module) main(process.argv.slice(2))

module.exports = {
  absoluteStringLocations,
  buildSummary,
  evidenceLevel,
  markdown,
  measuredTimeScope,
  passMarker,
  recordSchema,
  summarySchema,
  thresholdPolicy,
  validateRecord,
  validateSummary
}
