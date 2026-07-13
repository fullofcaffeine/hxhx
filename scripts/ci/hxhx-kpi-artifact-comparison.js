#!/usr/bin/env node
/**
 * Compare bytecode and native hxhx KPI reports from one measurement job.
 *
 * This is a diagnostic evidence boundary, not a performance threshold. It
 * refuses comparisons whose commit, runner, toolchains, method, or artifact
 * kinds differ so a fast-looking number cannot be produced from unlike runs.
 */

const fs = require('fs')
const {
  validateKpiReport
} = require('./hxhx-kpi-report-validator.js')

const schema = 'hxhx.kpi-artifact-comparison.v1'
const passMarker = 'HXHX_KPI_ARTIFACT_COMPARISON:PASS'

function parseArgs(argv) {
  const args = {
    bytecodeReport: null,
    nativeReport: null,
    jsonOut: null
  }
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index]
    if (value === '--bytecode-report') args.bytecodeReport = argv[++index]
    else if (value === '--native-report') args.nativeReport = argv[++index]
    else if (value === '--json-out') args.jsonOut = argv[++index]
    else throw new Error(`unknown argument: ${value}`)
  }
  if (!args.bytecodeReport || !args.nativeReport || !args.jsonOut) {
    throw new Error('expected --bytecode-report <report.json> --native-report <report.json> --json-out <comparison.json>')
  }
  return args
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    throw new Error(`${label} is not readable JSON: ${error.message}`)
  }
}

function median(samples) {
  const values = [...samples].sort((left, right) => left - right)
  const middle = Math.floor(values.length / 2)
  if (values.length % 2 === 1) return values[middle]
  return (values[middle - 1] + values[middle]) / 2
}

function metricKey(row) {
  return `${row.metric}\u0000${row.lane}\u0000${row.unit}`
}

function metricMap(report, label) {
  const result = new Map()
  for (const row of report.metrics) {
    const key = metricKey(row)
    if (result.has(key)) throw new Error(`${label} contains duplicate metric ${row.metric}/${row.lane}/${row.unit}`)
    result.set(key, row)
  }
  return result
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

/**
 * Builds a comparison only when the two reports describe the same experiment
 * apart from the compiler artifact being bytecode versus a native executable.
 */
function compareReports(bytecode, native) {
  const errors = []
  for (const [label, report] of [['bytecode report', bytecode], ['native report', native]]) {
    for (const error of validateKpiReport(report)) errors.push(`${label}: ${error}`)
  }
  if (errors.length > 0) throw new Error(errors.join('\n'))

  if (bytecode.environment.hxhx_artifact_kind !== 'ocaml-bytecode') {
    errors.push('bytecode report must identify hxhx_artifact_kind as ocaml-bytecode')
  }
  if (native.environment.hxhx_artifact_kind !== 'native-executable') {
    errors.push('native report must identify hxhx_artifact_kind as native-executable')
  }
  if (bytecode.git.commit !== native.git.commit) errors.push('reports must use the same commit SHA')
  if (!bytecode.git.tracked_source_clean || !native.git.tracked_source_clean) {
    errors.push('both reports must come from clean tracked source')
  }

  const sharedEnvironmentFields = [
    'platform',
    'os',
    'os_release',
    'architecture',
    'cpu_model',
    'python_version',
    'haxe_bin',
    'haxe_version',
    'node_version',
    'ocaml_version',
    'dune_version'
  ]
  for (const field of sharedEnvironmentFields) {
    if (bytecode.environment[field] !== native.environment[field]) {
      errors.push(`reports must use the same environment.${field}`)
    }
  }
  if (!sameJson(bytecode.config, native.config)) errors.push('reports must use the same benchmark config')
  if (!sameJson(bytecode.measurement, native.measurement)) {
    errors.push('reports must use the same measurement method')
  }

  let bytecodeMetrics
  let nativeMetrics
  try {
    bytecodeMetrics = metricMap(bytecode, 'bytecode report')
    nativeMetrics = metricMap(native, 'native report')
  } catch (error) {
    errors.push(error.message)
  }
  if (bytecodeMetrics && nativeMetrics) {
    const bytecodeKeys = [...bytecodeMetrics.keys()].sort()
    const nativeKeys = [...nativeMetrics.keys()].sort()
    if (!sameJson(bytecodeKeys, nativeKeys)) errors.push('reports must contain the same metric/lane rows')
  }
  if (errors.length > 0) throw new Error(errors.join('\n'))

  const metrics = [...bytecodeMetrics.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, bytecodeRow]) => {
      const nativeRow = nativeMetrics.get(key)
      const bytecodeMedian = median(bytecodeRow.summary.samples)
      const nativeMedian = median(nativeRow.summary.samples)
      return {
        metric: bytecodeRow.metric,
        lane: bytecodeRow.lane,
        unit: bytecodeRow.unit,
        bytecodeMedian,
        nativeMedian,
        nativeOverBytecode: bytecodeMedian === 0
          ? null
          : Number((nativeMedian / bytecodeMedian).toFixed(4))
      }
    })

  return {
    schema,
    generated_at_utc: new Date().toISOString(),
    diagnostic_only: true,
    git: {
      commit: bytecode.git.commit,
      tracked_source_clean: true
    },
    environment: Object.fromEntries(
      sharedEnvironmentFields.map(field => [field, bytecode.environment[field]])
    ),
    config: bytecode.config,
    measurement: bytecode.measurement,
    reports: {
      bytecode: {
        generated_at_utc: bytecode.generated_at_utc,
        hxhx_artifact_kind: bytecode.environment.hxhx_artifact_kind
      },
      native: {
        generated_at_utc: native.generated_at_utc,
        hxhx_artifact_kind: native.environment.hxhx_artifact_kind
      }
    },
    metrics
  }
}

function main(argv) {
  let args
  try {
    args = parseArgs(argv)
    const bytecode = readJson(args.bytecodeReport, 'bytecode report')
    const native = readJson(args.nativeReport, 'native report')
    const comparison = compareReports(bytecode, native)
    fs.writeFileSync(args.jsonOut, `${JSON.stringify(comparison, null, 2)}\n`)
  } catch (error) {
    for (const line of String(error.message).split('\n')) {
      console.error(`[hxhx-kpi-artifact-comparison] ERROR: ${line}`)
    }
    process.exit(1)
  }
  console.log('[ci:guards] OK: bytecode/native hxhx KPI reports are comparable')
  console.log(passMarker)
}

if (require.main === module) main(process.argv.slice(2))

module.exports = { compareReports, passMarker, schema }
