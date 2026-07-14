#!/usr/bin/env node

/**
 * Builds and validates report-only evidence for rebuilding native hxhx from
 * the committed OCaml snapshot without invoking upstream Haxe.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const {
  directoryDigest,
  isDigest,
  isIsoTimestamp,
  isNormalizedPath,
  isSha,
  nonEmptyString,
  normalizeToolLabel,
  numericSummary,
  parseBoolean,
  parseInteger,
  readJson,
  round,
  runTool,
  sameJson,
  sha256
} = require('./benchmark-report-common.js')

const schema = 'hxhx.stage0-free-build.v1'
const artifactKind = 'stage0-free-native-hxhx-build'
const evidenceLevel = 'diagnostic-report-only'
const passMarker = 'HXHX_STAGE0_FREE_BUILD_REPORT:PASS'
const resourceSchema = 'hxhx.command-resource-sample.v1'
const resourceScope = 'OS ru_maxrss for the completed build command child hierarchy; not simultaneous whole-machine or process-tree-sum memory'
const buildCommand = ['bash', 'scripts/hxhx/build-hxhx.sh']
const laneOrder = 'odd reps cache-disabled then cache-primed; even reps cache-primed then cache-disabled'
const repoRoot = path.resolve(__dirname, '../..')
const bootstrapPath = 'packages/hxhx/bootstrap_out'
const requiredSmokeTargets = ['js', 'ocaml']
const laneDefinitions = {
  'cache-disabled': {
    label: 'fresh workspace with Dune shared cache disabled',
    dune_cache: 'disabled',
    prime_runs: 0
  },
  'cache-primed': {
    label: 'fresh workspace with one private Dune shared-cache prime',
    dune_cache: 'enabled-except-user-rules',
    prime_runs: 1
  }
}
const measurementContract = {
  command: 'npm run hxhx:bench:stage0-free-build',
  source: 'scripts/hxhx/bench-stage0-free-build.sh',
  build_command: buildCommand,
  sample_scope: 'copy committed bootstrap snapshot into a fresh workspace and build native out.exe with Dune',
  validation_scope: 'artifact digest plus stage0-free hxhx target-list smoke; smoke time is excluded from build timing',
  rss_scope: resourceScope,
  workspace_state: 'new build workspace for every prime and measured sample',
  cache_state: 'cache-disabled never reads or writes a shared cache; cache-primed uses one private report-local cache primed once before samples',
  build_environment: {
    HAXE_BIN: '$UNUSABLE_HAXE_SENTINEL',
    HXHX_FORBID_STAGE0: '1',
    HXHX_FORCE_STAGE0: '0',
    HXHX_BOOTSTRAP_PREFER_NATIVE: '1',
    HXHX_STAGE0_OCAML_BUILD: 'native',
    HXHX_BOOTSTRAP_BUILD_DIR: '$REPORT_RUN/build',
    HXHX_BOOTSTRAP_BUILD_PRUNE: '0',
    HXHX_BOOTSTRAP_HEARTBEAT: '0',
    HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS: '0',
    DUNE_CACHE_ROOT: '$REPORT_PRIVATE_CACHE'
  },
  stage0_forbidden: true,
  upstream_haxe_used_by_build: false,
  artifact_kind_required: 'native .exe',
  threshold_policy: 'diagnostic report-only; no blocking threshold'
}

function fail(message) {
  console.error(`[stage0-free-build-benchmark-report] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const args = { command: argv[0] || '' }
  for (let index = 1; index < argv.length; index += 1) {
    const key = argv[index]
    if (!key.startsWith('--')) throw new Error(`unexpected argument: ${key}`)
    const value = argv[index + 1]
    if (value === undefined || value.startsWith('--')) throw new Error(`missing value for ${key}`)
    args[key.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value
    index += 1
  }
  return args
}

function requireArg(args, key) {
  if (!nonEmptyString(args[key])) throw new Error(`missing --${key.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`)}`)
  return args[key]
}

function relativeEvidencePath(filePath, reportsDir) {
  const resolvedDir = path.resolve(reportsDir)
  const resolvedFile = path.resolve(filePath)
  const relative = path.relative(resolvedDir, resolvedFile)
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`evidence must stay inside reports directory: ${filePath}`)
  }
  return relative.split(path.sep).join('/')
}

function expectedOrder(lane, rep) {
  const disabledFirst = rep % 2 === 1
  if (lane === 'cache-disabled') return disabledFirst ? 1 : 2
  if (lane === 'cache-primed') return disabledFirst ? 2 : 1
  return null
}

function validDuneJobs(value) {
  return value === 'auto' || /^[1-9][0-9]*$/.test(value || '')
}

function validateResourceSample(sample, lane, rep, owner) {
  const errors = []
  if (sample?.schema !== resourceSchema) errors.push(`${owner}.schema must be ${resourceSchema}`)
  if (sample?.label !== `${lane}.${rep}`) errors.push(`${owner}.label must match its lane and repetition`)
  if (!sameJson(sample?.command, buildCommand)) errors.push(`${owner}.command must match the stage0-free build command`)
  if (!isIsoTimestamp(sample?.started_at) || !isIsoTimestamp(sample?.ended_at)) {
    errors.push(`${owner} timestamps must be canonical ISO timestamps`)
  }
  if (!Number.isInteger(sample?.elapsed_ms) || sample.elapsed_ms < 1) errors.push(`${owner}.elapsed_ms must be positive`)
  if (!Number.isInteger(sample?.peak_child_rss_kb) || sample.peak_child_rss_kb < 1) {
    errors.push(`${owner}.peak_child_rss_kb must be positive`)
  }
  if (sample?.rss_scope !== resourceScope) errors.push(`${owner}.rss_scope must describe the measured memory boundary`)
  if (sample?.exit_code !== 0) errors.push(`${owner}.exit_code must be 0`)
  if (sample?.launch_error !== null) errors.push(`${owner}.launch_error must be null`)
  return errors
}

function parseResultsTsv(filePath) {
  const lines = fs.readFileSync(filePath, 'utf8').trim().split(/\r?\n/)
  const expectedHeader = 'lane\trep\torder\tresource_report\tstdout_log\tstderr_log\tartifact\tsmoke'
  if (lines[0] !== expectedHeader) throw new Error(`unexpected results header in ${filePath}`)
  return lines.slice(1).filter(Boolean).map((line, index) => {
    const fields = line.split('\t')
    if (fields.length !== 8) throw new Error(`results row ${index + 2} must have eight tab-separated fields`)
    return {
      lane: fields[0],
      rep: parseInteger(fields[1], `results row ${index + 2} rep`, 1),
      order: parseInteger(fields[2], `results row ${index + 2} order`, 1),
      resource_report: fields[3],
      stdout_log: fields[4],
      stderr_log: fields[5],
      artifact: fields[6],
      smoke: fields[7]
    }
  })
}

function smokeTargets(filePath) {
  return fs.readFileSync(filePath, 'utf8').split(/\r?\n/).map(value => value.trim()).filter(Boolean)
}

function evidenceRecord(filePath, reportsDir) {
  return {
    path: relativeEvidencePath(filePath, reportsDir),
    sha256: sha256(filePath),
    size_bytes: fs.statSync(filePath).size
  }
}

function buildRuns(rows, reportsDir, commit) {
  return rows.map(row => {
    if (!laneDefinitions[row.lane]) throw new Error(`unexpected lane in results: ${row.lane}`)
    for (const [field, label] of [
      ['resource_report', 'resource report'],
      ['stdout_log', 'stdout log'],
      ['stderr_log', 'stderr log'],
      ['artifact', 'native artifact'],
      ['smoke', 'smoke output']
    ]) {
      if (!fs.existsSync(row[field])) throw new Error(`${label} is missing: ${row[field]}`)
    }
    if (!row.artifact.endsWith('.exe')) throw new Error(`native artifact must end in .exe: ${row.artifact}`)
    const resource = readJson(row.resource_report, 'resource report')
    const resourceErrors = validateResourceSample(resource, row.lane, row.rep, row.resource_report)
    if (resourceErrors.length > 0) throw new Error(resourceErrors.join('\n'))
    const targets = smokeTargets(row.smoke)
    for (const target of requiredSmokeTargets) {
      if (!targets.includes(target)) throw new Error(`${row.smoke} does not prove required target ${target}`)
    }
    return {
      lane: row.lane,
      rep: row.rep,
      order: row.order,
      elapsed_ms: resource.elapsed_ms,
      peak_child_rss_kb: resource.peak_child_rss_kb,
      stage0_forbidden: true,
      artifact_commit: commit,
      resource: evidenceRecord(row.resource_report, reportsDir),
      stdout: evidenceRecord(row.stdout_log, reportsDir),
      stderr: evidenceRecord(row.stderr_log, reportsDir),
      artifact: {
        ...evidenceRecord(row.artifact, reportsDir),
        kind: 'native-executable'
      },
      smoke: {
        ...evidenceRecord(row.smoke, reportsDir),
        required_targets: requiredSmokeTargets
      }
    }
  })
}

function summarizeRuns(runs) {
  return Object.keys(laneDefinitions).map(lane => {
    const laneRuns = runs.filter(run => run.lane === lane).sort((left, right) => left.rep - right.rep)
    return {
      lane,
      elapsed_ms: numericSummary(laneRuns.map(run => run.elapsed_ms)),
      peak_child_rss_kb: numericSummary(laneRuns.map(run => run.peak_child_rss_kb))
    }
  })
}

function buildComparison(summaries) {
  const disabled = summaries.find(summary => summary.lane === 'cache-disabled')
  const primed = summaries.find(summary => summary.lane === 'cache-primed')
  if (!disabled || !primed || disabled.elapsed_ms.median <= 0) throw new Error('could not compare build lanes')
  return {
    baseline_lane: 'cache-disabled',
    candidate_lane: 'cache-primed',
    primed_over_disabled_elapsed: round(primed.elapsed_ms.median / disabled.elapsed_ms.median, 3),
    primed_over_disabled_peak_rss: disabled.peak_child_rss_kb.median === 0
      ? null
      : round(primed.peak_child_rss_kb.median / disabled.peak_child_rss_kb.median, 3),
    policy: 'report-only; no blocking threshold'
  }
}

function buildReport(args) {
  const resultsTsv = requireArg(args, 'resultsTsv')
  const reportsDir = requireArg(args, 'reportsDir')
  const gitCommit = requireArg(args, 'gitCommit')
  const reps = parseInteger(requireArg(args, 'reps'), '--reps', 1)
  const duneJobs = requireArg(args, 'duneJobs')
  const cacheStorageMode = requireArg(args, 'cacheStorageMode')
  if (!isSha(gitCommit)) throw new Error('--git-commit must be a 40-character SHA')
  if (!['auto', 'hardlink', 'copy'].includes(cacheStorageMode)) {
    throw new Error('--cache-storage-mode must be auto, hardlink, or copy')
  }
  if (args.cachePrimeCompleted !== 'true') throw new Error('--cache-prime-completed must be true')
  const runs = buildRuns(parseResultsTsv(resultsTsv), reportsDir, gitCommit)
  const summaries = summarizeRuns(runs)
  const snapshot = directoryDigest(path.join(repoRoot, bootstrapPath))
  return {
    schema,
    artifact_kind: artifactKind,
    evidence_level: evidenceLevel,
    marker: passMarker,
    recorded_at: new Date().toISOString(),
    git: {
      commit: gitCommit,
      tracked_source_clean_at_start: parseBoolean(requireArg(args, 'startClean'), '--start-clean'),
      tracked_source_clean_at_end: parseBoolean(requireArg(args, 'endClean'), '--end-clean')
    },
    environment: {
      os: os.type(),
      architecture: os.arch(),
      cpu_model: os.cpus()[0]?.model || 'unknown',
      node_version: process.version,
      haxe_path: normalizeToolLabel(runTool('which', ['haxe'], 'Haxe path', repoRoot), repoRoot),
      haxe_version: runTool('haxe', ['--version'], 'Haxe version', repoRoot),
      python_version: runTool('python3', ['--version'], 'Python version', repoRoot),
      ocamlc_version: runTool('ocamlc', ['-version'], 'OCaml bytecode compiler version', repoRoot),
      ocamlopt_version: runTool('ocamlopt', ['-version'], 'OCaml native compiler version', repoRoot),
      dune_version: runTool('dune', ['--version'], 'Dune version', repoRoot)
    },
    bootstrap_snapshot: {
      path: bootstrapPath,
      ...snapshot
    },
    config: {
      reps,
      dune_jobs: duneJobs,
      dune_cache_storage_mode: cacheStorageMode,
      lane_order: laneOrder,
      lanes: laneDefinitions,
      private_cache_prime_completed: true
    },
    measurement: measurementContract,
    runs,
    summaries,
    comparison: buildComparison(summaries)
  }
}

function validateNumericSummary(summary, values, owner, errors) {
  if (!summary || typeof summary !== 'object') {
    errors.push(`${owner} must be an object`)
    return
  }
  if (!sameJson(summary, numericSummary(values))) errors.push(`${owner} does not match raw run values`)
}

function validateReport(report) {
  const errors = []
  if (!report || typeof report !== 'object' || Array.isArray(report)) return ['report must be an object']
  if (report.schema !== schema) errors.push(`schema must be ${schema}`)
  if (report.artifact_kind !== artifactKind) errors.push(`artifact_kind must be ${artifactKind}`)
  if (report.evidence_level !== evidenceLevel) errors.push(`evidence_level must be ${evidenceLevel}`)
  if (report.marker !== passMarker) errors.push(`marker must be ${passMarker}`)
  if (!isIsoTimestamp(report.recorded_at)) errors.push('recorded_at must be a canonical ISO timestamp')
  if (!isSha(report.git?.commit)) errors.push('git.commit must be a 40-character SHA')
  for (const field of ['tracked_source_clean_at_start', 'tracked_source_clean_at_end']) {
    if (typeof report.git?.[field] !== 'boolean') errors.push(`git.${field} must be boolean`)
  }
  for (const field of [
    'os', 'architecture', 'cpu_model', 'node_version', 'haxe_path', 'haxe_version',
    'python_version', 'ocamlc_version', 'ocamlopt_version', 'dune_version'
  ]) {
    if (!nonEmptyString(report.environment?.[field])) errors.push(`environment.${field} must be a non-empty string`)
  }
  if (!isNormalizedPath(report.environment?.haxe_path)) errors.push('environment.haxe_path must be a safe non-absolute label')
  if (report.bootstrap_snapshot?.path !== bootstrapPath) errors.push(`bootstrap_snapshot.path must be ${bootstrapPath}`)
  if (!isDigest(report.bootstrap_snapshot?.sha256)) errors.push('bootstrap_snapshot.sha256 must be a SHA-256 digest')
  for (const field of ['file_count', 'byte_count']) {
    if (!Number.isInteger(report.bootstrap_snapshot?.[field]) || report.bootstrap_snapshot[field] < 1) {
      errors.push(`bootstrap_snapshot.${field} must be a positive integer`)
    }
  }
  const reps = report.config?.reps
  if (!Number.isInteger(reps) || reps < 1) errors.push('config.reps must be a positive integer')
  if (!validDuneJobs(report.config?.dune_jobs)) errors.push('config.dune_jobs must be auto or a positive integer')
  if (!['auto', 'hardlink', 'copy'].includes(report.config?.dune_cache_storage_mode)) {
    errors.push('config.dune_cache_storage_mode must be auto, hardlink, or copy')
  }
  if (report.config?.lane_order !== laneOrder) errors.push(`config.lane_order must be ${laneOrder}`)
  if (!sameJson(report.config?.lanes, laneDefinitions)) errors.push('config.lanes must match the build-lane contract')
  if (report.config?.private_cache_prime_completed !== true) errors.push('config.private_cache_prime_completed must be true')
  if (!sameJson(report.measurement, measurementContract)) errors.push('measurement must match the stage0-free build contract')

  const runs = Array.isArray(report.runs) ? report.runs : []
  if (!Array.isArray(report.runs)) errors.push('runs must be an array')
  if (Number.isInteger(reps) && runs.length !== reps * Object.keys(laneDefinitions).length) {
    errors.push('runs must contain exactly one row per lane and repetition')
  }
  const seen = new Set()
  for (let index = 0; index < runs.length; index += 1) {
    const run = runs[index]
    const owner = `runs[${index}]`
    const definition = laneDefinitions[run?.lane]
    if (!definition) errors.push(`${owner}.lane is invalid`)
    if (!Number.isInteger(run?.rep) || run.rep < 1 || (Number.isInteger(reps) && run.rep > reps)) {
      errors.push(`${owner}.rep is outside the configured range`)
    }
    if (definition && Number.isInteger(run?.rep) && run?.order !== expectedOrder(run.lane, run.rep)) {
      errors.push(`${owner}.order does not match the alternating lane order`)
    }
    if (!Number.isInteger(run?.elapsed_ms) || run.elapsed_ms < 1) errors.push(`${owner}.elapsed_ms must be positive`)
    if (!Number.isInteger(run?.peak_child_rss_kb) || run.peak_child_rss_kb < 1) {
      errors.push(`${owner}.peak_child_rss_kb must be positive`)
    }
    if (run?.stage0_forbidden !== true) errors.push(`${owner}.stage0_forbidden must be true`)
    if (run?.artifact_commit !== report.git?.commit) errors.push(`${owner}.artifact_commit must match git.commit`)
    const key = `${run?.lane}:${run?.rep}`
    if (seen.has(key)) errors.push(`${owner} duplicates ${key}`)
    seen.add(key)
    for (const field of ['resource', 'stdout', 'stderr', 'artifact', 'smoke']) {
      const evidence = run?.[field]
      if (!isNormalizedPath(evidence?.path)) errors.push(`${owner}.${field}.path must be safely report-relative`)
      if (!isDigest(evidence?.sha256)) errors.push(`${owner}.${field}.sha256 must be a SHA-256 digest`)
      if (!Number.isInteger(evidence?.size_bytes) || evidence.size_bytes < 0) {
        errors.push(`${owner}.${field}.size_bytes must be non-negative`)
      }
    }
    if (!run?.artifact?.path.endsWith('.exe')) errors.push(`${owner}.artifact.path must identify a native .exe`)
    if (run?.artifact?.kind !== 'native-executable') errors.push(`${owner}.artifact.kind must be native-executable`)
    for (const field of ['resource', 'stdout', 'artifact', 'smoke']) {
      if (run?.[field]?.size_bytes < 1) errors.push(`${owner}.${field}.size_bytes must be positive`)
    }
    if (!sameJson(run?.smoke?.required_targets, requiredSmokeTargets)) {
      errors.push(`${owner}.smoke.required_targets must match the smoke contract`)
    }
  }

  if (!Array.isArray(report.summaries) || report.summaries.length !== Object.keys(laneDefinitions).length) {
    errors.push('summaries must contain one entry per lane')
  } else {
    const seenLanes = new Set()
    for (let index = 0; index < report.summaries.length; index += 1) {
      const summary = report.summaries[index]
      const owner = `summaries[${index}]`
      if (!laneDefinitions[summary?.lane]) errors.push(`${owner}.lane is invalid`)
      if (seenLanes.has(summary?.lane)) errors.push(`${owner}.lane must be unique`)
      seenLanes.add(summary?.lane)
      const laneRuns = runs.filter(run => run.lane === summary?.lane).sort((left, right) => left.rep - right.rep)
      if (laneRuns.length > 0) {
        validateNumericSummary(summary.elapsed_ms, laneRuns.map(run => run.elapsed_ms), `${owner}.elapsed_ms`, errors)
        validateNumericSummary(summary.peak_child_rss_kb, laneRuns.map(run => run.peak_child_rss_kb), `${owner}.peak_child_rss_kb`, errors)
      }
    }
  }
  if (Array.isArray(report.summaries) && report.summaries.length === 2) {
    try {
      if (!sameJson(report.comparison, buildComparison(report.summaries))) errors.push('comparison does not match lane medians')
    } catch (error) {
      errors.push(`comparison could not be computed: ${error.message}`)
    }
  }
  return errors
}

function evidencePath(reportDir, evidence, owner, errors) {
  if (!isNormalizedPath(evidence?.path)) return null
  const resolved = path.resolve(reportDir, evidence.path)
  const relative = path.relative(reportDir, resolved)
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    errors.push(`${owner}.path escapes the report directory`)
    return null
  }
  if (!fs.existsSync(resolved)) {
    errors.push(`${owner}.path is missing: ${evidence.path}`)
    return null
  }
  if (sha256(resolved) !== evidence.sha256) errors.push(`${owner}.sha256 does not match ${evidence.path}`)
  if (fs.statSync(resolved).size !== evidence.size_bytes) errors.push(`${owner}.size_bytes does not match ${evidence.path}`)
  return resolved
}

function validateEvidenceFiles(report, reportPath) {
  const errors = []
  const reportDir = path.dirname(path.resolve(reportPath))
  if (!Array.isArray(report?.runs)) return errors
  for (let index = 0; index < report.runs.length; index += 1) {
    const run = report.runs[index]
    const resourcePath = evidencePath(reportDir, run.resource, `runs[${index}].resource`, errors)
    evidencePath(reportDir, run.stdout, `runs[${index}].stdout`, errors)
    evidencePath(reportDir, run.stderr, `runs[${index}].stderr`, errors)
    evidencePath(reportDir, run.artifact, `runs[${index}].artifact`, errors)
    const smokePath = evidencePath(reportDir, run.smoke, `runs[${index}].smoke`, errors)
    if (resourcePath) {
      try {
        const resource = readJson(resourcePath, 'resource report')
        errors.push(...validateResourceSample(resource, run.lane, run.rep, `runs[${index}].resource`))
        if (resource.elapsed_ms !== run.elapsed_ms) errors.push(`runs[${index}].elapsed_ms does not match its resource report`)
        if (resource.peak_child_rss_kb !== run.peak_child_rss_kb) {
          errors.push(`runs[${index}].peak_child_rss_kb does not match its resource report`)
        }
      } catch (error) {
        errors.push(`runs[${index}].resource is invalid: ${error.message}`)
      }
    }
    if (smokePath) {
      const targets = smokeTargets(smokePath)
      for (const target of requiredSmokeTargets) {
        if (!targets.includes(target)) errors.push(`runs[${index}].smoke does not contain required target ${target}`)
      }
    }
  }
  try {
    const currentCommit = runTool('git', ['rev-parse', 'HEAD'], 'current Git commit', repoRoot)
    if (currentCommit === report.git?.commit) {
      const currentSnapshot = directoryDigest(path.join(repoRoot, bootstrapPath))
      if (!sameJson(currentSnapshot, {
        sha256: report.bootstrap_snapshot.sha256,
        file_count: report.bootstrap_snapshot.file_count,
        byte_count: report.bootstrap_snapshot.byte_count
      })) {
        errors.push('bootstrap_snapshot does not match the current exact-commit checkout')
      }
    }
  } catch (error) {
    errors.push(`could not validate current bootstrap snapshot: ${error.message}`)
  }
  return errors
}

function markdown(report) {
  const byLane = new Map(report.summaries.map(summary => [summary.lane, summary]))
  const disabled = byLane.get('cache-disabled')
  const primed = byLane.get('cache-primed')
  return [
    '### Stage0-free native hxhx build benchmark',
    '',
    `- Commit: \`${report.git.commit}\``,
    `- Machine: \`${report.environment.os} ${report.environment.architecture}\` — \`${report.environment.cpu_model}\``,
    `- Toolchains: OCaml native \`${report.environment.ocamlopt_version}\`, Dune \`${report.environment.dune_version}\``,
    `- Repetitions: \`${report.config.reps}\` per lane`,
    '- Upstream Haxe used by measured build: `no`',
    '- Evidence level: `diagnostic / report-only`',
    '',
    '| Clean build state | Median build | Raw build samples | Median child peak RSS |',
    '|---|---:|---|---:|',
    `| shared cache disabled | ${disabled.elapsed_ms.median}ms | ${disabled.elapsed_ms.samples.join(', ')} | ${disabled.peak_child_rss_kb.median} KiB |`,
    `| private cache primed once | ${primed.elapsed_ms.median}ms | ${primed.elapsed_ms.samples.join(', ')} | ${primed.peak_child_rss_kb.median} KiB |`,
    '',
    `Primed-cache / disabled-cache median: \`${report.comparison.primed_over_disabled_elapsed}x\` (report-only).`,
    '',
    `Memory scope: ${resourceScope}.`,
    ''
  ].join('\n')
}

function main(argv) {
  try {
    const args = parseArgs(argv)
    if (args.command === 'build') {
      const report = buildReport(args)
      const errors = validateReport(report)
      if (errors.length > 0) throw new Error(errors.join('\n'))
      fs.mkdirSync(path.dirname(requireArg(args, 'jsonOut')), { recursive: true })
      fs.writeFileSync(args.jsonOut, `${JSON.stringify(report, null, 2)}\n`)
      console.log(`[stage0-free-build-benchmark-report] wrote ${args.jsonOut}`)
      return
    }
    if (args.command === 'validate') {
      const reportPath = requireArg(args, 'report')
      const report = readJson(reportPath, 'benchmark report')
      const errors = [...validateReport(report), ...validateEvidenceFiles(report, reportPath)]
      if (errors.length > 0) throw new Error(errors.join('\n'))
      console.log(passMarker)
      console.log('[ci:guards] OK: stage0-free build benchmark report is self-describing')
      return
    }
    if (args.command === 'markdown') {
      const reportPath = requireArg(args, 'report')
      const report = readJson(reportPath, 'benchmark report')
      const errors = [...validateReport(report), ...validateEvidenceFiles(report, reportPath)]
      if (errors.length > 0) throw new Error(errors.join('\n'))
      process.stdout.write(markdown(report))
      return
    }
    throw new Error('usage: stage0-free-build-benchmark-report.js <build|validate|markdown> [options]')
  } catch (error) {
    fail(error.message)
  }
}

if (require.main === module) main(process.argv.slice(2))

module.exports = {
  artifactKind,
  buildComparison,
  buildCommand,
  evidenceLevel,
  laneDefinitions,
  laneOrder,
  measurementContract,
  passMarker,
  requiredSmokeTargets,
  resourceSchema,
  resourceScope,
  schema,
  summarizeRuns,
  validateEvidenceFiles,
  validateReport,
  validateResourceSample
}
