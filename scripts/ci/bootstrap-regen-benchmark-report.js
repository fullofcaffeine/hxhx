#!/usr/bin/env node
/**
 * Build and validate self-describing bootstrap-regeneration benchmark reports.
 *
 * The benchmark remains diagnostic. This module preserves the raw run rows and
 * binds them to a commit, runner, toolchain set, measurement configuration, and
 * the low-level regeneration reports that produced each row.
 */

const childProcess = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const schema = 'hxhx.bootstrap-regen-benchmark.v1'
const passMarker = 'HXHX_BOOTSTRAP_REGEN_REPORT:PASS'
const artifactKind = 'bootstrap-snapshot-regeneration'
const repoRoot = path.resolve(__dirname, '../..')

const scenarioDefinitions = {
  cold: 'full regeneration after removing prior generated output',
  warm: 'forced incremental regeneration while reusing the repository Haxe server',
  skip: 'unchanged-input check after one unmeasured fingerprint-priming regeneration',
  select: 'stage0 compiler selection only; no snapshot regeneration'
}

const expectedTsvHeader = [
  'scenario',
  'policy',
  'dune_jobs',
  'rep',
  'elapsed_sec',
  'emit_sec',
  'total_sec',
  'skipped_emit',
  'haxe_mode',
  'haxe_policy',
  'switched',
  'peak_rss_mb',
  'report'
]

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0
}

function isNormalizedPath(value) {
  return nonEmptyString(value)
    && !path.isAbsolute(value)
    && !/^[A-Za-z]:[\\/]/.test(value)
    && !value.startsWith('~')
    && !value.split(/[\\/]/).includes('..')
}

function isSha(value) {
  return /^[0-9a-f]{40}$/i.test(value || '')
}

function isDigest(value) {
  return /^[0-9a-f]{64}$/i.test(value || '')
}

function parseBoolean(value, label) {
  if (value === true || value === 'true' || value === '1' || value === 1) return true
  if (value === false || value === 'false' || value === '0' || value === 0) return false
  throw new Error(`${label} must be true/false or 1/0`)
}

function parseNonNegativeNumber(value, label) {
  const parsed = Number(value)
  if (!Number.isFinite(parsed) || parsed < 0) throw new Error(`${label} must be a non-negative number`)
  return parsed
}

function parsePositiveInteger(value, label) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${label} must be a positive integer`)
  return parsed
}

function parseList(value, label) {
  const values = String(value || '')
    .split(',')
    .map(entry => entry.trim())
    .filter(Boolean)
  if (values.length === 0) throw new Error(`${label} must contain at least one value`)
  if (new Set(values).size !== values.length) throw new Error(`${label} must not contain duplicate values`)
  return values
}

function median(values) {
  const ordered = [...values].sort((left, right) => left - right)
  const middle = Math.floor(ordered.length / 2)
  if (ordered.length % 2 === 1) return ordered[middle]
  return (ordered[middle - 1] + ordered[middle]) / 2
}

function numericSummary(values) {
  return {
    count: values.length,
    min: Math.min(...values),
    max: Math.max(...values),
    median: median(values),
    samples: [...values]
  }
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

function normalizedToolLabel(value) {
  if (!nonEmptyString(value)) return 'auto'
  if (!path.isAbsolute(value)) return value
  const relative = path.relative(repoRoot, value)
  if (relative && !relative.startsWith('..') && !path.isAbsolute(relative)) {
    return relative.split(path.sep).join('/')
  }
  return path.basename(value)
}

function toolVersion(command, args, label) {
  const result = childProcess.spawnSync(command, args, {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== 0) {
    throw new Error(`could not read ${label} version from ${command}: ${(result.stderr || result.stdout || '').trim()}`)
  }
  const output = `${result.stdout || ''}\n${result.stderr || ''}`.trim().split(/\r?\n/)[0]
  if (!output) throw new Error(`${label} version output was empty`)
  return output
}

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function relativeReportPath(filePath, reportsDir) {
  const resolvedDir = path.resolve(reportsDir)
  const resolvedFile = path.resolve(filePath)
  const relative = path.relative(resolvedDir, resolvedFile)
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`run report must be inside the benchmark report directory: ${filePath}`)
  }
  return relative.split(path.sep).join('/')
}

function parseResultsTsv(filePath) {
  const lines = fs.readFileSync(filePath, 'utf8').trimEnd().split(/\r?\n/)
  if (lines.length < 2) throw new Error('results TSV must contain a header and at least one run row')
  const header = lines[0].split('\t')
  if (!sameJson(header, expectedTsvHeader)) {
    throw new Error(`unexpected results TSV header: ${header.join(',')}`)
  }
  return lines.slice(1).map((line, lineIndex) => {
    const cells = line.split('\t')
    if (cells.length !== header.length) {
      throw new Error(`results TSV line ${lineIndex + 2} has ${cells.length} cells; expected ${header.length}`)
    }
    return Object.fromEntries(header.map((field, index) => [field, cells[index]]))
  })
}

function readLowLevelReport(filePath) {
  let report
  try {
    report = JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    throw new Error(`could not read low-level run report ${filePath}: ${error.message}`)
  }
  if (!report || typeof report !== 'object' || Array.isArray(report)) {
    throw new Error(`low-level run report must be a JSON object: ${filePath}`)
  }
  return report
}

function lowLevelNumber(report, owner, field) {
  const value = report[field]
  return parseNonNegativeNumber(value, `${owner}.${field}`)
}

/**
 * Reconciles one human-readable TSV row with its primary JSON report. The
 * aggregate never trusts copied timing values when the source artifact differs.
 */
function buildRun(row, reportsDir, index) {
  const owner = `results row ${index + 1}`
  const reportPath = path.resolve(row.report)
  const relativePath = relativeReportPath(reportPath, reportsDir)
  const source = readLowLevelReport(reportPath)
  if (source.status !== 'ok' || source.exit_code !== 0) {
    throw new Error(`${relativePath} must describe a successful regeneration run`)
  }
  const emitSec = parseNonNegativeNumber(row.emit_sec, `${owner}.emit_sec`)
  const totalSec = parseNonNegativeNumber(row.total_sec, `${owner}.total_sec`)
  const skippedEmit = parseBoolean(row.skipped_emit, `${owner}.skipped_emit`)
  const switched = parseBoolean(row.switched, `${owner}.switched`)
  const peakRssMb = parseNonNegativeNumber(row.peak_rss_mb, `${owner}.peak_rss_mb`)

  if (!source.phase_seconds || typeof source.phase_seconds !== 'object') {
    throw new Error(`${relativePath} must include phase_seconds`)
  }
  if (!source.stage0_observability || typeof source.stage0_observability !== 'object') {
    throw new Error(`${relativePath} must include stage0_observability`)
  }
  const comparisons = [
    ['emit_sec', emitSec, lowLevelNumber(source.phase_seconds, `${relativePath}.phase_seconds`, 'emit')],
    ['total_sec', totalSec, lowLevelNumber(source.phase_seconds, `${relativePath}.phase_seconds`, 'total')],
    ['skipped_emit', skippedEmit, parseBoolean(source.skipped_emit, `${relativePath}.skipped_emit`)],
    ['haxe_mode', row.haxe_mode, source.haxe_bin_mode],
    ['haxe_policy', row.haxe_policy, source.haxe_bin_policy],
    ['switched', switched, parseBoolean(source.haxe_bin_switched, `${relativePath}.haxe_bin_switched`)],
    [
      'peak_rss_mb',
      peakRssMb,
      lowLevelNumber(source.stage0_observability, `${relativePath}.stage0_observability`, 'heartbeat_peak_rss_mb')
    ]
  ]
  for (const [field, rowValue, sourceValue] of comparisons) {
    if (rowValue !== sourceValue) {
      throw new Error(`${owner}.${field} does not match ${relativePath}`)
    }
  }

  return {
    scenario: row.scenario,
    policy: row.policy,
    dune_jobs: row.dune_jobs,
    rep: parsePositiveInteger(row.rep, `${owner}.rep`),
    elapsed_sec: parseNonNegativeNumber(row.elapsed_sec, `${owner}.elapsed_sec`),
    emit_sec: emitSec,
    total_sec: totalSec,
    skipped_emit: skippedEmit,
    haxe_bin_mode: row.haxe_mode,
    haxe_bin_policy: row.haxe_policy,
    haxe_bin_switched: switched,
    haxe_version: nonEmptyString(source.haxe_version) ? source.haxe_version : 'unknown',
    haxe_native_candidate: normalizedToolLabel(source.haxe_native_candidate),
    peak_rss_mb: peakRssMb,
    source_report: {
      path: relativePath,
      sha256: sha256(reportPath)
    }
  }
}

function expectedPolicies(config) {
  if (config.compare_stage0_policies) return ['wrapper', 'native']
  return [config.stage0_policy_override || 'default']
}

function runKey(run) {
  return `${run.scenario}\u0000${run.policy}\u0000${run.dune_jobs}\u0000${run.rep}`
}

function groupKey(run) {
  return `${run.scenario}\u0000${run.policy}\u0000${run.dune_jobs}`
}

function buildSummaries(runs) {
  const groups = new Map()
  for (const run of runs) {
    const key = groupKey(run)
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(run)
  }
  return [...groups.values()]
    .map(group => {
      const ordered = [...group].sort((left, right) => left.rep - right.rep)
      return {
        scenario: ordered[0].scenario,
        policy: ordered[0].policy,
        dune_jobs: ordered[0].dune_jobs,
        elapsed_sec: numericSummary(ordered.map(run => run.elapsed_sec)),
        emit_sec: numericSummary(ordered.map(run => run.emit_sec)),
        total_sec: numericSummary(ordered.map(run => run.total_sec)),
        peak_rss_mb: numericSummary(ordered.map(run => run.peak_rss_mb))
      }
    })
    .sort((left, right) => groupKey(left).localeCompare(groupKey(right)))
}

/**
 * Builds one comparable artifact from the benchmark configuration, raw rows,
 * low-level reports, current toolchains, and source-state provenance.
 */
function buildReport(args) {
  const scenarios = parseList(args.scenarios, '--scenarios')
  const duneJobs = parseList(args.duneJobs, '--dune-jobs')
  const config = {
    scenarios,
    reps: parsePositiveInteger(args.reps, '--reps'),
    verify_snapshots: parseBoolean(args.verify, '--verify'),
    dune_jobs: duneJobs,
    compare_stage0_policies: parseBoolean(args.compareStage0Policies, '--compare-stage0-policies'),
    stage0_policy_override: args.stage0Policy || '',
    stage0_native_candidate: normalizedToolLabel(args.stage0NativeBin),
    stage0_no_opt: parseBoolean(args.stage0NoOpt, '--stage0-no-opt'),
    stage0_no_inline: parseBoolean(args.stage0NoInline, '--stage0-no-inline'),
    stage0_disable_prepasses: parseBoolean(args.stage0DisablePrepasses, '--stage0-disable-prepasses'),
    stage0_ocamlrunparam: args.stage0Ocamlrunparam || ''
  }
  const rows = parseResultsTsv(args.resultsTsv)
  const runs = rows.map((row, index) => buildRun(row, args.reportsDir, index))
  const haxeBin = process.env.HAXE_BIN || 'haxe'
  const report = {
    schema,
    artifact_kind: artifactKind,
    generated_at_utc: new Date().toISOString(),
    diagnostic_only: true,
    git: {
      commit: args.gitCommit,
      tracked_source_clean_at_start: parseBoolean(args.startClean, '--start-tracked-source-clean'),
      tracked_source_clean_at_end: parseBoolean(args.endClean, '--end-tracked-source-clean')
    },
    environment: {
      os: os.type(),
      os_release: os.release(),
      architecture: os.arch(),
      cpu_model: (os.cpus()[0] && os.cpus()[0].model) || 'unknown',
      haxe_bin: normalizedToolLabel(haxeBin),
      haxe_version: toolVersion(haxeBin, ['-version'], 'Haxe'),
      node_version: process.version,
      ocaml_version: toolVersion('ocamlc', ['-version'], 'OCaml'),
      dune_version: toolVersion('dune', ['--version'], 'Dune')
    },
    config,
    measurement: {
      command: 'npm run hxhx:bench:bootstrap-regen',
      source: 'scripts/hxhx/bench-bootstrap-regen.sh',
      elapsed_clock: 'wall-clock seconds',
      threshold_policy: 'report-only',
      raw_runs_embedded: true,
      per_run_reports_retained: true,
      scenario_definitions: scenarioDefinitions,
      warmup_rules: {
        cold: 'none',
        warm: 'no explicit warmup; repetitions reuse the repository Haxe server',
        skip: 'one unmeasured forced incremental regeneration before each measured unchanged-input check',
        select: 'none'
      }
    },
    run_count: runs.length,
    runs,
    summaries: buildSummaries(runs)
  }
  const errors = validateReport(report)
  if (errors.length > 0) throw new Error(errors.join('\n'))
  return report
}

function validateNumericSummary(summary, owner, expected, errors) {
  if (!summary || typeof summary !== 'object' || Array.isArray(summary)) {
    errors.push(`${owner} must be an object`)
    return
  }
  if (!sameJson(summary, expected)) errors.push(`${owner} must match the raw run samples`)
}

/**
 * Validates both report shape and internal evidence consistency. In particular,
 * every configured run must exist and every summary must be recomputable from
 * the embedded raw rows.
 */
function validateReport(report) {
  const errors = []
  if (!report || typeof report !== 'object' || Array.isArray(report)) return ['report must be a JSON object']
  if (report.schema !== schema) errors.push(`schema must be ${schema}`)
  if (report.artifact_kind !== artifactKind) errors.push(`artifact_kind must be ${artifactKind}`)
  if (report.diagnostic_only !== true) errors.push('diagnostic_only must be true')
  if (!nonEmptyString(report.generated_at_utc) || Number.isNaN(Date.parse(report.generated_at_utc))) {
    errors.push('generated_at_utc must be an ISO timestamp')
  }

  const git = report.git
  if (!git || typeof git !== 'object') {
    errors.push('git must be an object')
  } else {
    if (!isSha(git.commit)) errors.push('git.commit must be a 40-character commit SHA')
    for (const field of ['tracked_source_clean_at_start', 'tracked_source_clean_at_end']) {
      if (typeof git[field] !== 'boolean') errors.push(`git.${field} must be boolean`)
    }
  }

  const environment = report.environment
  const environmentFields = [
    'os', 'os_release', 'architecture', 'cpu_model', 'haxe_bin', 'haxe_version',
    'node_version', 'ocaml_version', 'dune_version'
  ]
  if (!environment || typeof environment !== 'object') {
    errors.push('environment must be an object')
  } else {
    for (const field of environmentFields) {
      if (!nonEmptyString(environment[field])) errors.push(`environment.${field} must be a non-empty string`)
    }
    if (nonEmptyString(environment.haxe_bin) && !isNormalizedPath(environment.haxe_bin)) {
      errors.push('environment.haxe_bin must not contain a machine-local absolute path')
    }
  }

  const config = report.config
  if (!config || typeof config !== 'object') {
    errors.push('config must be an object')
  } else {
    if (!Array.isArray(config.scenarios) || config.scenarios.length === 0) {
      errors.push('config.scenarios must be a non-empty array')
    } else {
      if (new Set(config.scenarios).size !== config.scenarios.length) errors.push('config.scenarios must be unique')
      for (const scenario of config.scenarios) {
        if (!Object.hasOwn(scenarioDefinitions, scenario)) errors.push(`config.scenarios contains invalid scenario ${scenario}`)
      }
    }
    if (!Number.isInteger(config.reps) || config.reps <= 0) errors.push('config.reps must be a positive integer')
    if (typeof config.verify_snapshots !== 'boolean') errors.push('config.verify_snapshots must be boolean')
    if (!Array.isArray(config.dune_jobs) || config.dune_jobs.length === 0) {
      errors.push('config.dune_jobs must be a non-empty array')
    } else {
      if (new Set(config.dune_jobs).size !== config.dune_jobs.length) errors.push('config.dune_jobs must be unique')
      for (const value of config.dune_jobs) {
        if (value !== 'auto' && !/^[1-9][0-9]*$/.test(value)) errors.push(`config.dune_jobs contains invalid value ${value}`)
      }
    }
    if (typeof config.compare_stage0_policies !== 'boolean') errors.push('config.compare_stage0_policies must be boolean')
    if (typeof config.stage0_policy_override !== 'string') errors.push('config.stage0_policy_override must be a string')
    if (typeof config.stage0_policy_override === 'string'
        && !['', 'warn', 'prefer-native', 'require-native'].includes(config.stage0_policy_override)) {
      errors.push('config.stage0_policy_override must be empty, warn, prefer-native, or require-native')
    }
    if (config.compare_stage0_policies && config.stage0_policy_override) {
      errors.push('config.stage0_policy_override must be empty when comparing policies')
    }
    if (!nonEmptyString(config.stage0_native_candidate) || !isNormalizedPath(config.stage0_native_candidate)) {
      errors.push('config.stage0_native_candidate must be a normalized tool label')
    }
    for (const field of ['stage0_no_opt', 'stage0_no_inline', 'stage0_disable_prepasses']) {
      if (typeof config[field] !== 'boolean') errors.push(`config.${field} must be boolean`)
    }
    if (typeof config.stage0_ocamlrunparam !== 'string') errors.push('config.stage0_ocamlrunparam must be a string')
  }

  const measurement = report.measurement
  if (!measurement || typeof measurement !== 'object') {
    errors.push('measurement must be an object')
  } else {
    if (measurement.command !== 'npm run hxhx:bench:bootstrap-regen') errors.push('measurement.command is invalid')
    if (measurement.source !== 'scripts/hxhx/bench-bootstrap-regen.sh') errors.push('measurement.source is invalid')
    if (measurement.elapsed_clock !== 'wall-clock seconds') errors.push('measurement.elapsed_clock is invalid')
    if (measurement.threshold_policy !== 'report-only') errors.push('measurement.threshold_policy must be report-only')
    if (measurement.raw_runs_embedded !== true) errors.push('measurement.raw_runs_embedded must be true')
    if (measurement.per_run_reports_retained !== true) errors.push('measurement.per_run_reports_retained must be true')
    if (!sameJson(measurement.scenario_definitions, scenarioDefinitions)) {
      errors.push('measurement.scenario_definitions must describe the supported scenarios')
    }
    if (!measurement.warmup_rules || typeof measurement.warmup_rules !== 'object') {
      errors.push('measurement.warmup_rules must be an object')
    } else {
      for (const scenario of Object.keys(scenarioDefinitions)) {
        if (!nonEmptyString(measurement.warmup_rules[scenario])) {
          errors.push(`measurement.warmup_rules.${scenario} must be a non-empty string`)
        }
      }
    }
  }

  const runs = Array.isArray(report.runs) ? report.runs : []
  if (runs.length === 0) errors.push('runs must be a non-empty array')
  if (!Number.isInteger(report.run_count) || report.run_count !== runs.length) {
    errors.push('run_count must match runs.length')
  }
  const seenRuns = new Set()
  const seenReports = new Set()
  for (let index = 0; index < runs.length; index += 1) {
    const run = runs[index]
    const owner = `runs[${index}]`
    if (!run || typeof run !== 'object' || Array.isArray(run)) {
      errors.push(`${owner} must be an object`)
      continue
    }
    if (!Object.hasOwn(scenarioDefinitions, run.scenario)) errors.push(`${owner}.scenario is invalid`)
    if (!nonEmptyString(run.policy)) errors.push(`${owner}.policy must be a non-empty string`)
    if (!nonEmptyString(run.dune_jobs)) errors.push(`${owner}.dune_jobs must be a non-empty string`)
    if (!Number.isInteger(run.rep) || run.rep <= 0) errors.push(`${owner}.rep must be a positive integer`)
    for (const field of ['elapsed_sec', 'emit_sec', 'total_sec', 'peak_rss_mb']) {
      if (typeof run[field] !== 'number' || !Number.isFinite(run[field]) || run[field] < 0) {
        errors.push(`${owner}.${field} must be a non-negative finite number`)
      }
    }
    for (const field of ['skipped_emit', 'haxe_bin_switched']) {
      if (typeof run[field] !== 'boolean') errors.push(`${owner}.${field} must be boolean`)
    }
    for (const field of ['haxe_bin_mode', 'haxe_bin_policy', 'haxe_version', 'haxe_native_candidate']) {
      if (!nonEmptyString(run[field])) errors.push(`${owner}.${field} must be a non-empty string`)
    }
    if (nonEmptyString(run.haxe_native_candidate) && !isNormalizedPath(run.haxe_native_candidate)) {
      errors.push(`${owner}.haxe_native_candidate must be a normalized tool label`)
    }
    if (!run.source_report || typeof run.source_report !== 'object') {
      errors.push(`${owner}.source_report must be an object`)
    } else {
      if (!isNormalizedPath(run.source_report.path)) errors.push(`${owner}.source_report.path must be relative and normalized`)
      if (!isDigest(run.source_report.sha256)) errors.push(`${owner}.source_report.sha256 must be a SHA-256 digest`)
      if (seenReports.has(run.source_report.path)) errors.push(`${owner}.source_report.path must be unique`)
      seenReports.add(run.source_report.path)
    }
    const key = runKey(run)
    if (seenRuns.has(key)) errors.push(`${owner} duplicates scenario/policy/dune_jobs/rep ${key}`)
    seenRuns.add(key)
  }

  if (config && Array.isArray(config.scenarios) && Array.isArray(config.dune_jobs)
      && Number.isInteger(config.reps) && config.reps > 0
      && typeof config.compare_stage0_policies === 'boolean'
      && typeof config.stage0_policy_override === 'string') {
    const expected = new Set()
    for (const scenario of config.scenarios) {
      for (const policy of expectedPolicies(config)) {
        for (const duneJobs of config.dune_jobs) {
          for (let rep = 1; rep <= config.reps; rep += 1) {
            expected.add(runKey({ scenario, policy, dune_jobs: duneJobs, rep }))
          }
        }
      }
    }
    if (!sameJson([...seenRuns].sort(), [...expected].sort())) {
      errors.push('runs must contain exactly one row for every configured scenario/policy/dune-jobs/repetition combination')
    }
  }

  const summaries = Array.isArray(report.summaries) ? report.summaries : []
  if (summaries.length === 0) {
    errors.push('summaries must be a non-empty array')
  } else if (runs.length > 0) {
    const expected = buildSummaries(runs)
    if (summaries.length !== expected.length) errors.push('summaries must contain one row for each raw-run group')
    const expectedByKey = new Map(expected.map(summary => [groupKey(summary), summary]))
    const seen = new Set()
    for (let index = 0; index < summaries.length; index += 1) {
      const summary = summaries[index]
      const owner = `summaries[${index}]`
      if (!summary || typeof summary !== 'object') {
        errors.push(`${owner} must be an object`)
        continue
      }
      const key = groupKey(summary)
      if (seen.has(key)) errors.push(`${owner} duplicates a summary group`)
      seen.add(key)
      const expectedSummary = expectedByKey.get(key)
      if (!expectedSummary) {
        errors.push(`${owner} has no matching raw-run group`)
        continue
      }
      for (const field of ['elapsed_sec', 'emit_sec', 'total_sec', 'peak_rss_mb']) {
        validateNumericSummary(summary[field], `${owner}.${field}`, expectedSummary[field], errors)
      }
    }
  }
  return errors
}

function parseBuildArgs(argv) {
  const mapping = {
    '--results-tsv': 'resultsTsv',
    '--reports-dir': 'reportsDir',
    '--json-out': 'jsonOut',
    '--git-commit': 'gitCommit',
    '--start-tracked-source-clean': 'startClean',
    '--end-tracked-source-clean': 'endClean',
    '--scenarios': 'scenarios',
    '--reps': 'reps',
    '--verify': 'verify',
    '--dune-jobs': 'duneJobs',
    '--compare-stage0-policies': 'compareStage0Policies',
    '--stage0-policy': 'stage0Policy',
    '--stage0-native-bin': 'stage0NativeBin',
    '--stage0-no-opt': 'stage0NoOpt',
    '--stage0-no-inline': 'stage0NoInline',
    '--stage0-disable-prepasses': 'stage0DisablePrepasses',
    '--stage0-ocamlrunparam': 'stage0Ocamlrunparam'
  }
  const args = {}
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index]
    const field = mapping[flag]
    if (!field) throw new Error(`unknown build argument: ${flag}`)
    if (index + 1 >= argv.length) throw new Error(`missing value for ${flag}`)
    args[field] = argv[++index]
  }
  for (const field of Object.values(mapping)) {
    if (args[field] === undefined) throw new Error(`missing build argument for ${field}`)
  }
  return args
}

function readReport(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    throw new Error(`could not read report JSON: ${error.message}`)
  }
}

function markdown(report) {
  const lines = [
    '### Bootstrap regeneration benchmark',
    '',
    `- Commit: \`${report.git.commit}\``,
    `- Tracked source clean at start/end: \`${report.git.tracked_source_clean_at_start}\` / \`${report.git.tracked_source_clean_at_end}\``,
    `- Machine: \`${report.environment.os} ${report.environment.architecture}\` — \`${report.environment.cpu_model}\``,
    `- Toolchains: Haxe \`${report.environment.haxe_version}\`, OCaml \`${report.environment.ocaml_version}\`, Dune \`${report.environment.dune_version}\`, Node \`${report.environment.node_version}\``,
    '- Evidence level: `diagnostic / report-only`',
    '',
    '| Scenario | Stage0 policy | Dune jobs | Runs | Median elapsed | Median emit | Peak RSS median |',
    '|---|---|---:|---:|---:|---:|---:|'
  ]
  for (const summary of report.summaries) {
    lines.push(`| ${summary.scenario} | ${summary.policy} | ${summary.dune_jobs} | ${summary.elapsed_sec.count} | ${summary.elapsed_sec.median}s | ${summary.emit_sec.median}s | ${summary.peak_rss_mb.median} MB |`)
  }
  return `${lines.join('\n')}\n`
}

function printErrors(errors) {
  for (const error of errors) console.error(`[bootstrap-regen-benchmark-report] ERROR: ${error}`)
}

function main(argv) {
  const mode = argv[0]
  try {
    if (mode === 'build') {
      const args = parseBuildArgs(argv.slice(1))
      const report = buildReport(args)
      fs.writeFileSync(args.jsonOut, `${JSON.stringify(report, null, 2)}\n`)
      console.log(`[bootstrap-regen-benchmark-report] wrote ${args.jsonOut}`)
      console.log(passMarker)
      return
    }
    if ((mode === 'validate' || mode === 'markdown') && argv.length === 3 && argv[1] === '--report') {
      const report = readReport(argv[2])
      const errors = validateReport(report)
      if (errors.length > 0) {
        printErrors(errors)
        process.exit(1)
      }
      if (mode === 'markdown') process.stdout.write(markdown(report))
      else {
        console.log('[ci:guards] OK: bootstrap regeneration benchmark report is self-describing')
        console.log(passMarker)
      }
      return
    }
    throw new Error('usage: build <arguments> | validate --report <report.json> | markdown --report <report.json>')
  } catch (error) {
    printErrors(String(error.message).split('\n'))
    process.exit(1)
  }
}

if (require.main === module) main(process.argv.slice(2))

module.exports = {
  artifactKind,
  buildSummaries,
  passMarker,
  scenarioDefinitions,
  schema,
  validateReport
}
