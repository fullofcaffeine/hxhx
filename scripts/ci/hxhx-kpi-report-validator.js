#!/usr/bin/env node
/**
 * Validate that an hxhx KPI report is reproducible and self-describing.
 *
 * The benchmark numbers are useful only when a later reader can identify the
 * exact source commit, runner, toolchains, measurement method, and raw samples
 * that produced them. This module is shared by focused fixtures and the Full1
 * performance adapter so report-only and release evidence use one contract.
 */

const fs = require('fs')
const path = require('path')

const schema = 'hxhx.kpi.v2'
const passMarker = 'HXHX_KPI_REPORT_CONTRACT:PASS'

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0
}

function isNormalizedPath(value) {
  return nonEmptyString(value)
    && !path.isAbsolute(value)
    && !/^[A-Za-z]:[\\/]/.test(value)
    && !value.startsWith('~')
}

function validateKpiReport(report) {
  const errors = []
  if (!report || typeof report !== 'object' || Array.isArray(report)) {
    return ['report must be a JSON object']
  }
  if (report.schema !== schema) errors.push(`schema must be ${schema}`)
  if (!nonEmptyString(report.generated_at_utc) || Number.isNaN(Date.parse(report.generated_at_utc))) {
    errors.push('generated_at_utc must be an ISO timestamp')
  }

  const config = report.config
  if (!config || typeof config !== 'object') {
    errors.push('config must be an object')
  } else {
    if (!Number.isInteger(config.reps) || config.reps <= 0) {
      errors.push('config.reps must be a positive integer')
    }
    if (typeof config.run_macro_lane !== 'boolean') {
      errors.push('config.run_macro_lane must be boolean')
    }
  }

  const git = report.git
  if (!git || typeof git !== 'object') {
    errors.push('git must be an object')
  } else {
    if (!/^[0-9a-f]{40}$/i.test(git.commit || '')) {
      errors.push('git.commit must be a 40-character commit SHA')
    }
    if (typeof git.tracked_source_clean !== 'boolean') {
      errors.push('git.tracked_source_clean must be boolean')
    }
  }

  const environment = report.environment
  const environmentFields = [
    'platform',
    'os',
    'os_release',
    'architecture',
    'cpu_model',
    'python_version',
    'haxe_bin',
    'haxe_version',
    'hxhx_bin',
    'hxhx_artifact_kind',
    'node_version',
    'ocaml_version',
    'dune_version'
  ]
  if (!environment || typeof environment !== 'object') {
    errors.push('environment must be an object')
  } else {
    for (const field of environmentFields) {
      if (!nonEmptyString(environment[field])) {
        errors.push(`environment.${field} must be a non-empty string`)
      }
    }
    for (const field of ['haxe_bin', 'hxhx_bin']) {
      if (nonEmptyString(environment[field]) && !isNormalizedPath(environment[field])) {
        errors.push(`environment.${field} must not contain a machine-local absolute path`)
      }
    }
  }

  const measurement = report.measurement
  if (!measurement || typeof measurement !== 'object') {
    errors.push('measurement must be an object')
  } else {
    if (measurement.command !== 'npm run hxhx:bench:kpi') {
      errors.push('measurement.command must be npm run hxhx:bench:kpi')
    }
    if (measurement.source !== 'scripts/hxhx/bench-kpi.sh') {
      errors.push('measurement.source must be scripts/hxhx/bench-kpi.sh')
    }
    if (!Number.isInteger(measurement.repetitions) || measurement.repetitions <= 0) {
      errors.push('measurement.repetitions must be a positive integer')
    } else if (config && measurement.repetitions !== config.reps) {
      errors.push('measurement.repetitions must match config.reps')
    }
    if (measurement.raw_samples_embedded !== true) {
      errors.push('measurement.raw_samples_embedded must be true')
    }
    const expectedMetricMethods = [
      'compile_wall_ms',
      'incremental_rebuild_ms',
      'macro_overhead_ms',
      'peak_rss_kb'
    ]
    if (!measurement.warmup_runs || typeof measurement.warmup_runs !== 'object') {
      errors.push('measurement.warmup_runs must be an object')
    } else {
      for (const metric of expectedMetricMethods) {
        const value = measurement.warmup_runs[metric]
        if (!Number.isInteger(value) || value < 0) {
          errors.push(`measurement.warmup_runs.${metric} must be a non-negative integer`)
        }
      }
    }
    if (!measurement.states || typeof measurement.states !== 'object') {
      errors.push('measurement.states must be an object')
    } else {
      for (const metric of expectedMetricMethods) {
        if (!nonEmptyString(measurement.states[metric])) {
          errors.push(`measurement.states.${metric} must explain what the sample measures`)
        }
      }
    }
  }

  if (!Array.isArray(report.metrics) || report.metrics.length === 0) {
    errors.push('metrics must be a non-empty array')
  } else {
    for (let index = 0; index < report.metrics.length; index += 1) {
      const metric = report.metrics[index]
      const owner = `metrics[${index}]`
      if (!metric || typeof metric !== 'object') {
        errors.push(`${owner} must be an object`)
        continue
      }
      for (const field of ['metric', 'lane', 'unit']) {
        if (!nonEmptyString(metric[field])) errors.push(`${owner}.${field} must be a non-empty string`)
      }
      const summary = metric.summary
      if (!summary || typeof summary !== 'object') {
        errors.push(`${owner}.summary must be an object`)
        continue
      }
      if (!Number.isInteger(summary.count) || summary.count <= 0) {
        errors.push(`${owner}.summary.count must be a positive integer`)
      }
      if (!Array.isArray(summary.samples) || summary.samples.length === 0) {
        errors.push(`${owner}.summary.samples must be a non-empty array`)
      } else {
        if (summary.samples.some(value => typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
          errors.push(`${owner}.summary.samples must contain only non-negative finite numbers`)
        }
        if (summary.count !== summary.samples.length) {
          errors.push(`${owner}.summary.count must match summary.samples.length`)
        }
        if (config && Number.isInteger(config.reps) && summary.samples.length !== config.reps) {
          errors.push(`${owner}.summary.samples.length must match config.reps`)
        }
      }
    }
  }

  return errors
}

function main(argv) {
  if (argv.length !== 2 || argv[0] !== '--report') {
    console.error('Usage: node scripts/ci/hxhx-kpi-report-validator.js --report <report.json>')
    process.exit(2)
  }
  let report
  try {
    report = JSON.parse(fs.readFileSync(argv[1], 'utf8'))
  } catch (error) {
    console.error(`[hxhx-kpi-report-validator] ERROR: ${error.message}`)
    process.exit(1)
  }
  const errors = validateKpiReport(report)
  if (errors.length > 0) {
    for (const error of errors) console.error(`[hxhx-kpi-report-validator] ERROR: ${error}`)
    process.exit(1)
  }
  console.log('[ci:guards] OK: hxhx KPI report is self-describing')
  console.log(passMarker)
}

if (require.main === module) main(process.argv.slice(2))

module.exports = { passMarker, schema, validateKpiReport }
