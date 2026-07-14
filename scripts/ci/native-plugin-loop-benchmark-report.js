#!/usr/bin/env node

/**
 * Builds and validates report-only timing evidence for the real native plugin
 * author loop. Each numeric sample must be backed by a passing Full1 plugin
 * proof, so a failed build/load/runtime path cannot look like fast evidence.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const {
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

const schema = 'hxhx.native-plugin-loop.v1'
const artifactKind = 'native-plugin-author-loop'
const passMarker = 'HXHX_NATIVE_PLUGIN_LOOP_REPORT:PASS'
const routeOrder = 'odd reps upstream then hxhx; even reps hxhx then upstream'
const repoRoot = path.resolve(__dirname, '../..')
const routeDefinitions = {
  'upstream-to-hxhx': {
    label: 'upstream Haxe builds the plugin; hxhx loads and uses it',
    marker: 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS',
    command: 'bash scripts/ci/run-full1-plugin-upstream-to-hxhx-proof.sh'
  },
  'hxhx-to-hxhx': {
    label: 'stage0-forbidden hxhx builds, loads, and uses the plugin',
    marker: 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS',
    command: 'bash scripts/ci/run-full1-plugin-hxhx-to-hxhx-proof.sh'
  }
}

function fail(message) {
  console.error(`[native-plugin-loop-benchmark-report] ERROR: ${message}`)
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
    throw new Error(`proof summary must stay inside reports directory: ${filePath}`)
  }
  return relative.split(path.sep).join('/')
}

function validateProofSummary(summary, route, commit, filePath) {
  const definition = routeDefinitions[route]
  if (!definition) throw new Error(`unknown proof route: ${route}`)
  if (summary.schema !== 'full1-plugin-proof.v1') {
    throw new Error(`${filePath} has unexpected proof schema: ${summary.schema}`)
  }
  if (summary.synthetic !== false) throw new Error(`${filePath} must be real, not synthetic evidence`)
  if (summary.route !== route) throw new Error(`${filePath} route does not match ${route}`)
  if (summary.candidateSha !== commit) throw new Error(`${filePath} candidate SHA does not match ${commit}`)
  if (summary.marker !== definition.marker || summary.result !== definition.marker) {
    throw new Error(`${filePath} does not contain the passing ${route} marker`)
  }
  if (!isDigest(summary.plugin?.artifactSha256)) {
    throw new Error(`${filePath} is missing the verified plugin artifact digest`)
  }
  if (!isNormalizedPath(summary.plugin?.evidenceArtifact)) {
    throw new Error(`${filePath} is missing a safe evidence plugin-artifact path`)
  }
  if (summary.sampleCompile?.selectedImpl !== 'provider/js-native-wrapper'
      || summary.sampleCompile?.runtimeStdout !== 'sum=6') {
    throw new Error(`${filePath} does not prove the expected plugin-backed sample runtime`)
  }
  if (route === 'hxhx-to-hxhx'
      && (summary.pluginCompiler?.kind !== 'hxhx-stage3' || summary.pluginCompiler?.stage0Forbidden !== true)) {
    throw new Error(`${filePath} does not prove stage0-forbidden hxhx plugin compilation`)
  }
  if (route === 'upstream-to-hxhx' && summary.hostCompiler?.kind !== 'upstream-haxe') {
    throw new Error(`${filePath} does not identify the upstream-Haxe baseline compiler`)
  }
}

function validateProofArtifact(summary, summaryPath) {
  const summaryDir = path.dirname(path.resolve(summaryPath))
  const artifactPath = path.resolve(summaryDir, summary.plugin.evidenceArtifact)
  const relative = path.relative(summaryDir, artifactPath)
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`${summaryPath} plugin artifact escapes its proof directory`)
  }
  if (!fs.existsSync(artifactPath)) throw new Error(`${summaryPath} plugin artifact is missing: ${relative}`)
  if (sha256(artifactPath) !== summary.plugin.artifactSha256) {
    throw new Error(`${summaryPath} plugin artifact digest does not match ${relative}`)
  }
}

function parseResultsTsv(filePath) {
  const lines = fs.readFileSync(filePath, 'utf8').trim().split(/\r?\n/)
  const expectedHeader = 'route\trep\torder\telapsed_ms\tsummary'
  if (lines[0] !== expectedHeader) throw new Error(`unexpected results header in ${filePath}`)
  return lines.slice(1).filter(Boolean).map((line, index) => {
    const fields = line.split('\t')
    if (fields.length !== 5) throw new Error(`results row ${index + 2} must have five tab-separated fields`)
    return {
      route: fields[0],
      rep: parseInteger(fields[1], `results row ${index + 2} rep`, 1),
      order: parseInteger(fields[2], `results row ${index + 2} order`, 1),
      elapsed_ms: parseInteger(fields[3], `results row ${index + 2} elapsed_ms`, 0),
      summary: fields[4]
    }
  })
}

function buildRuns(rows, reportsDir, commit) {
  return rows.map(row => {
    if (!routeDefinitions[row.route]) throw new Error(`unexpected route in results: ${row.route}`)
    const proofSummary = readJson(row.summary, 'plugin proof summary')
    validateProofSummary(proofSummary, row.route, commit, row.summary)
    validateProofArtifact(proofSummary, row.summary)
    return {
      route: row.route,
      rep: row.rep,
      order: row.order,
      elapsed_ms: row.elapsed_ms,
      proof: {
        summary_path: relativeEvidencePath(row.summary, reportsDir),
        summary_sha256: sha256(row.summary),
        marker: routeDefinitions[row.route].marker,
        candidate_sha: proofSummary.candidateSha,
        plugin_artifact_sha256: proofSummary.plugin.artifactSha256
      }
    }
  })
}

function summarizeRuns(runs) {
  return Object.keys(routeDefinitions).map(route => {
    const routeRuns = runs.filter(run => run.route === route).sort((left, right) => left.rep - right.rep)
    return {
      route,
      elapsed_ms: numericSummary(routeRuns.map(run => run.elapsed_ms))
    }
  })
}

function expectedOrder(route, rep) {
  const upstreamFirst = rep % 2 === 1
  if (route === 'upstream-to-hxhx') return upstreamFirst ? 1 : 2
  if (route === 'hxhx-to-hxhx') return upstreamFirst ? 2 : 1
  return null
}

function buildComparison(summaries) {
  const baseline = summaries.find(summary => summary.route === 'upstream-to-hxhx')?.elapsed_ms.median
  const candidate = summaries.find(summary => summary.route === 'hxhx-to-hxhx')?.elapsed_ms.median
  if (!Number.isFinite(baseline) || !Number.isFinite(candidate) || baseline <= 0) {
    throw new Error('could not compute plugin-loop comparison medians')
  }
  return {
    baseline_route: 'upstream-to-hxhx',
    candidate_route: 'hxhx-to-hxhx',
    hxhx_over_upstream: round(candidate / baseline, 3),
    hxhx_speedup_percent: round(((baseline - candidate) / baseline) * 100, 1),
    policy: 'report-only; no blocking threshold'
  }
}

function buildReport(args) {
  const resultsTsv = requireArg(args, 'resultsTsv')
  const reportsDir = requireArg(args, 'reportsDir')
  const gitCommit = requireArg(args, 'gitCommit')
  const hxhxCommit = requireArg(args, 'hxhxCommit')
  const hxhxBin = requireArg(args, 'hxhxBin')
  if (!isSha(gitCommit)) throw new Error('--git-commit must be a 40-character SHA')
  if (hxhxCommit !== gitCommit) throw new Error('--hxhx-commit must match --git-commit')
  if (!fs.existsSync(hxhxBin)) throw new Error(`hxhx artifact does not exist: ${hxhxBin}`)
  if (!hxhxBin.endsWith('.exe')) throw new Error('native plugin-loop evidence requires a native hxhx .exe artifact')

  const reps = parseInteger(requireArg(args, 'reps'), '--reps', 1)
  const warmups = parseInteger(requireArg(args, 'warmups'), '--warmups', 0)
  const rows = parseResultsTsv(resultsTsv)
  const runs = buildRuns(rows, reportsDir, gitCommit)
  const summaries = summarizeRuns(runs)
  const cpu = os.cpus()[0]?.model || 'unknown'
  return {
    schema,
    artifact_kind: artifactKind,
    evidence_level: 'diagnostic-report-only',
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
      cpu_model: cpu,
      node_version: process.version,
      haxe_path: normalizeToolLabel(runTool('which', ['haxe'], 'Haxe path', repoRoot), repoRoot),
      haxe_version: runTool('haxe', ['--version'], 'Haxe version', repoRoot),
      ocamlc_version: runTool('ocamlc', ['-version'], 'OCaml bytecode compiler version', repoRoot),
      ocamlopt_version: runTool('ocamlopt', ['-version'], 'OCaml native compiler version', repoRoot),
      dune_version: runTool('dune', ['--version'], 'Dune version', repoRoot),
      hxhx_artifact_kind: 'native',
      hxhx_artifact_path: normalizeToolLabel(hxhxBin, repoRoot),
      hxhx_artifact_commit: hxhxCommit,
      hxhx_artifact_sha256: sha256(hxhxBin)
    },
    config: {
      reps,
      warmups,
      route_order: routeOrder
    },
    measurement: {
      command: 'npm run hxhx:bench:native-plugin-loop',
      sample_scope: 'fresh plugin emit, Dune plugin build, hxhx plugin load, sample compile, and sample runtime',
      preparation_scope: 'native hxhx executable preparation is timed separately and excluded from route samples',
      warmup_rule: warmups === 0
        ? 'no warmup runs'
        : `${warmups} unrecorded correctness warmup run(s) per route using fresh proof directories`,
      state_rule: 'every recorded route sample uses a new temporary proof workspace and must emit a passing Full1 proof summary',
      route_definitions: routeDefinitions
    },
    hxhx_preparation: {
      provided_by_caller: parseBoolean(requireArg(args, 'hxhxProvided'), '--hxhx-provided'),
      elapsed_ms: parseInteger(requireArg(args, 'hxhxPreparationMs'), '--hxhx-preparation-ms', 0),
      command: 'HXHX_FORBID_STAGE0=1 HXHX_BOOTSTRAP_PREFER_NATIVE=1 HXHX_STAGE0_OCAML_BUILD=native bash scripts/hxhx/build-hxhx.sh'
    },
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
  const expected = numericSummary(values)
  if (!sameJson(summary, expected)) errors.push(`${owner} does not match raw run values`)
}

function validateReport(report) {
  const errors = []
  if (!report || typeof report !== 'object' || Array.isArray(report)) return ['report must be an object']
  if (report.schema !== schema) errors.push(`schema must be ${schema}`)
  if (report.artifact_kind !== artifactKind) errors.push(`artifact_kind must be ${artifactKind}`)
  if (report.evidence_level !== 'diagnostic-report-only') errors.push('evidence_level must be diagnostic-report-only')
  if (report.marker !== passMarker) errors.push(`marker must be ${passMarker}`)
  if (!isIsoTimestamp(report.recorded_at)) {
    errors.push('recorded_at must be a canonical ISO timestamp')
  }

  if (!isSha(report.git?.commit)) errors.push('git.commit must be a 40-character SHA')
  for (const field of ['tracked_source_clean_at_start', 'tracked_source_clean_at_end']) {
    if (typeof report.git?.[field] !== 'boolean') errors.push(`git.${field} must be boolean`)
  }

  const environment = report.environment
  for (const field of [
    'os',
    'architecture',
    'cpu_model',
    'node_version',
    'haxe_path',
    'haxe_version',
    'ocamlc_version',
    'ocamlopt_version',
    'dune_version',
    'hxhx_artifact_path'
  ]) {
    if (!nonEmptyString(environment?.[field])) errors.push(`environment.${field} must be a non-empty string`)
  }
  if (environment?.hxhx_artifact_kind !== 'native') errors.push('environment.hxhx_artifact_kind must be native')
  if (!isNormalizedPath(environment?.haxe_path)) errors.push('environment.haxe_path must be a safe non-absolute label')
  if (!isNormalizedPath(environment?.hxhx_artifact_path)) errors.push('environment.hxhx_artifact_path must be a safe non-absolute label')
  if (environment?.hxhx_artifact_commit !== report.git?.commit) errors.push('environment.hxhx_artifact_commit must match git.commit')
  if (!isDigest(environment?.hxhx_artifact_sha256)) errors.push('environment.hxhx_artifact_sha256 must be a SHA-256 digest')

  const reps = report.config?.reps
  const warmups = report.config?.warmups
  if (!Number.isInteger(reps) || reps < 1) errors.push('config.reps must be a positive integer')
  if (!Number.isInteger(warmups) || warmups < 0) errors.push('config.warmups must be a non-negative integer')
  if (report.config?.route_order !== routeOrder) errors.push(`config.route_order must be ${routeOrder}`)
  for (const field of ['command', 'sample_scope', 'preparation_scope', 'warmup_rule', 'state_rule']) {
    if (!nonEmptyString(report.measurement?.[field])) errors.push(`measurement.${field} must be a non-empty string`)
  }
  if (!sameJson(report.measurement?.route_definitions, routeDefinitions)) {
    errors.push('measurement.route_definitions must match the benchmark contract')
  }
  if (typeof report.hxhx_preparation?.provided_by_caller !== 'boolean') {
    errors.push('hxhx_preparation.provided_by_caller must be boolean')
  }
  if (!Number.isInteger(report.hxhx_preparation?.elapsed_ms) || report.hxhx_preparation.elapsed_ms < 0) {
    errors.push('hxhx_preparation.elapsed_ms must be a non-negative integer')
  }
  if (!nonEmptyString(report.hxhx_preparation?.command)) errors.push('hxhx_preparation.command must be described')

  const runs = Array.isArray(report.runs) ? report.runs : []
  if (!Array.isArray(report.runs)) errors.push('runs must be an array')
  if (Number.isInteger(reps) && runs.length !== reps * Object.keys(routeDefinitions).length) {
    errors.push('runs must contain exactly one row per route and repetition')
  }
  const seen = new Set()
  for (let index = 0; index < runs.length; index += 1) {
    const run = runs[index]
    const owner = `runs[${index}]`
    const definition = routeDefinitions[run?.route]
    if (!definition) errors.push(`${owner}.route is invalid`)
    if (!Number.isInteger(run?.rep) || run.rep < 1 || (Number.isInteger(reps) && run.rep > reps)) {
      errors.push(`${owner}.rep is outside the configured range`)
    }
    if (![1, 2].includes(run?.order)) errors.push(`${owner}.order must be 1 or 2`)
    if (definition && Number.isInteger(run?.rep) && run?.order !== expectedOrder(run.route, run.rep)) {
      errors.push(`${owner}.order does not match the alternating route order`)
    }
    if (!Number.isInteger(run?.elapsed_ms) || run.elapsed_ms < 0) errors.push(`${owner}.elapsed_ms must be non-negative`)
    const key = `${run?.route}:${run?.rep}`
    if (seen.has(key)) errors.push(`${owner} duplicates ${key}`)
    seen.add(key)
    if (!isNormalizedPath(run?.proof?.summary_path)) errors.push(`${owner}.proof.summary_path must be safely report-relative`)
    if (!isDigest(run?.proof?.summary_sha256)) errors.push(`${owner}.proof.summary_sha256 must be a SHA-256 digest`)
    if (definition && run?.proof?.marker !== definition.marker) errors.push(`${owner}.proof.marker does not match its route`)
    if (run?.proof?.candidate_sha !== report.git?.commit) errors.push(`${owner}.proof.candidate_sha must match git.commit`)
    if (!isDigest(run?.proof?.plugin_artifact_sha256)) errors.push(`${owner}.proof.plugin_artifact_sha256 must be a SHA-256 digest`)
  }

  if (!Array.isArray(report.summaries) || report.summaries.length !== Object.keys(routeDefinitions).length) {
    errors.push('summaries must contain one entry per route')
  } else {
    const seenRoutes = new Set()
    for (let index = 0; index < report.summaries.length; index += 1) {
      const summary = report.summaries[index]
      const owner = `summaries[${index}]`
      if (!routeDefinitions[summary?.route]) errors.push(`${owner}.route is invalid`)
      if (seenRoutes.has(summary?.route)) errors.push(`${owner}.route must be unique`)
      seenRoutes.add(summary?.route)
      const values = runs.filter(run => run.route === summary?.route).sort((a, b) => a.rep - b.rep).map(run => run.elapsed_ms)
      if (values.length > 0) validateNumericSummary(summary.elapsed_ms, values, `${owner}.elapsed_ms`, errors)
    }
  }

  if (Array.isArray(report.summaries) && report.summaries.length === 2) {
    try {
      const expected = buildComparison(report.summaries)
      if (!sameJson(report.comparison, expected)) errors.push('comparison does not match route medians')
    } catch (error) {
      errors.push(`comparison could not be computed: ${error.message}`)
    }
  }
  return errors
}

function validateEvidenceFiles(report, reportPath) {
  const errors = []
  const reportDir = path.dirname(path.resolve(reportPath))
  if (!Array.isArray(report?.runs)) return errors
  for (let index = 0; index < report.runs.length; index += 1) {
    const run = report.runs[index]
    const owner = `runs[${index}].proof`
    if (!isNormalizedPath(run?.proof?.summary_path)) continue
    const summaryPath = path.resolve(reportDir, run.proof.summary_path)
    const relative = path.relative(reportDir, summaryPath)
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
      errors.push(`${owner}.summary_path escapes the report directory`)
      continue
    }
    if (!fs.existsSync(summaryPath)) {
      errors.push(`${owner}.summary_path is missing: ${run.proof.summary_path}`)
      continue
    }
    const actualDigest = sha256(summaryPath)
    if (actualDigest !== run.proof.summary_sha256) {
      errors.push(`${owner}.summary_sha256 does not match ${run.proof.summary_path}`)
      continue
    }
    try {
      const proofSummary = readJson(summaryPath, 'plugin proof summary')
      validateProofSummary(proofSummary, run.route, report.git.commit, summaryPath)
      validateProofArtifact(proofSummary, summaryPath)
      if (proofSummary.plugin.artifactSha256 !== run.proof.plugin_artifact_sha256) {
        errors.push(`${owner}.plugin_artifact_sha256 does not match ${run.proof.summary_path}`)
      }
    } catch (error) {
      errors.push(`${owner} is invalid: ${error.message}`)
    }
  }
  return errors
}

function markdown(report) {
  const summaryByRoute = new Map(report.summaries.map(summary => [summary.route, summary]))
  const baseline = summaryByRoute.get('upstream-to-hxhx')
  const candidate = summaryByRoute.get('hxhx-to-hxhx')
  return [
    '### Native plugin author-loop benchmark',
    '',
    `- Commit: \`${report.git.commit}\``,
    `- Machine: \`${report.environment.os} ${report.environment.architecture}\` — \`${report.environment.cpu_model}\``,
    `- Toolchains: Haxe \`${report.environment.haxe_version}\`, OCaml native \`${report.environment.ocamlopt_version}\`, Dune \`${report.environment.dune_version}\``,
    `- Native hxhx preparation: \`${report.hxhx_preparation.elapsed_ms}ms\` (excluded from route samples)`,
    `- Repetitions/warmups: \`${report.config.reps}\` / \`${report.config.warmups}\``,
    '- Evidence level: `diagnostic / report-only`',
    '',
    '| Route | Median full loop | Raw samples |',
    '|---|---:|---|',
    `| upstream Haxe builds plugin | ${baseline.elapsed_ms.median}ms | ${baseline.elapsed_ms.samples.join(', ')} |`,
    `| native hxhx builds plugin | ${candidate.elapsed_ms.median}ms | ${candidate.elapsed_ms.samples.join(', ')} |`,
    '',
    `Native hxhx / upstream-Haxe median: \`${report.comparison.hxhx_over_upstream}x\` (${report.comparison.hxhx_speedup_percent}% speedup; report-only).`,
    ''
  ].join('\n')
}

function readReport(filePath) {
  return readJson(filePath, 'benchmark report')
}

function main(argv) {
  let args
  try {
    args = parseArgs(argv)
    if (args.command === 'build') {
      const report = buildReport(args)
      const errors = validateReport(report)
      if (errors.length > 0) throw new Error(errors.join('\n'))
      fs.mkdirSync(path.dirname(requireArg(args, 'jsonOut')), { recursive: true })
      fs.writeFileSync(args.jsonOut, `${JSON.stringify(report, null, 2)}\n`)
      console.log(`[native-plugin-loop-benchmark-report] wrote ${args.jsonOut}`)
      return
    }
    if (args.command === 'validate') {
      const reportPath = requireArg(args, 'report')
      const report = readReport(reportPath)
      const errors = [...validateReport(report), ...validateEvidenceFiles(report, reportPath)]
      if (errors.length > 0) throw new Error(errors.join('\n'))
      console.log(passMarker)
      console.log('[ci:guards] OK: native plugin-loop benchmark report is self-describing')
      return
    }
    if (args.command === 'markdown') {
      const reportPath = requireArg(args, 'report')
      const report = readReport(reportPath)
      const errors = [...validateReport(report), ...validateEvidenceFiles(report, reportPath)]
      if (errors.length > 0) throw new Error(errors.join('\n'))
      process.stdout.write(markdown(report))
      return
    }
    throw new Error('usage: native-plugin-loop-benchmark-report.js <build|validate|markdown> [options]')
  } catch (error) {
    fail(error.message)
  }
}

if (require.main === module) main(process.argv.slice(2))

module.exports = {
  artifactKind,
  buildComparison,
  numericSummary,
  passMarker,
  routeDefinitions,
  routeOrder,
  schema,
  summarizeRuns,
  validateEvidenceFiles,
  validateReport
}
