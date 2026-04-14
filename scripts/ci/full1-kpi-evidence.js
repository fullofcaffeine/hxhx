#!/usr/bin/env node
/**
 * Convert the existing HXHX KPI report into Full1 perf evidence.
 *
 * The KPI harness remains the workload runner. This adapter only reshapes its
 * stable hxhx.kpi.v1 JSON into the evaluator input schema and intentionally
 * maps exactly one native hxhx lane to the normalized `hxhx` lane name.
 */

const fs = require('fs')
const path = require('path')

function usage() {
  console.error(`Usage: node scripts/ci/full1-kpi-evidence.js --kpi-report <report.json> --json-out <evidence.json>

Options:
  --kpi-report <path>  hxhx.kpi.v1 report from npm run hxhx:bench:kpi
  --json-out <path>    Full1 perf evidence JSON output path
  --hxhx-lane <lane>   KPI lane to compare against upstream_haxe (default: ocaml_metal_builtin)
`)
}

function fail(message, code = 2) {
  console.error(`[full1-kpi-evidence] ERROR: ${message}`)
  process.exit(code)
}

function parseArgs(argv) {
  const parsed = {
    kpiReport: null,
    jsonOut: null,
    hxhxLane: 'ocaml_metal_builtin'
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--kpi-report') {
      i += 1
      if (i >= argv.length) fail('missing value for --kpi-report')
      parsed.kpiReport = argv[i]
    } else if (arg === '--json-out') {
      i += 1
      if (i >= argv.length) fail('missing value for --json-out')
      parsed.jsonOut = argv[i]
    } else if (arg === '--hxhx-lane') {
      i += 1
      if (i >= argv.length) fail('missing value for --hxhx-lane')
      parsed.hxhxLane = argv[i]
    } else if (arg === '--help' || arg === '-h') {
      usage()
      process.exit(0)
    } else {
      fail(`unknown argument: ${arg}`)
    }
  }
  if (!parsed.kpiReport) fail('--kpi-report is required')
  if (!parsed.jsonOut) fail('--json-out is required')
  return parsed
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function metricSamples(report, metric, lane) {
  const entry = report.metrics.find(item => item.metric === metric && item.lane === lane)
  if (!entry || !entry.summary || !Array.isArray(entry.summary.samples)) return null
  const values = entry.summary.samples.map(Number).filter(Number.isFinite)
  return values.length === 0 ? null : values
}

function gitMetadata() {
  return {
    sha: process.env.GITHUB_SHA || null,
    ref: process.env.GITHUB_REF || null,
    run_id: process.env.GITHUB_RUN_ID || null,
    run_attempt: process.env.GITHUB_RUN_ATTEMPT || null
  }
}

function main() {
  const parsed = parseArgs(process.argv.slice(2))
  const report = readJson(parsed.kpiReport)
  if (!report || report.schema !== 'hxhx.kpi.v1') {
    fail(`unexpected KPI report schema: ${report && report.schema}`)
  }
  if (!Array.isArray(report.metrics)) fail('KPI report must include metrics[]')

  const requiredMetrics = ['compile_wall_ms', 'incremental_rebuild_ms', 'macro_overhead_ms', 'peak_rss_kb']
  const samples = []
  const missing = []
  for (const metric of requiredMetrics) {
    const upstreamValues = metricSamples(report, metric, 'upstream_haxe')
    const hxhxValues = metricSamples(report, metric, parsed.hxhxLane)
    if (!upstreamValues) missing.push(`${metric}:upstream_haxe`)
    if (!hxhxValues) missing.push(`${metric}:${parsed.hxhxLane}`)
    if (upstreamValues) {
      samples.push({
        metric,
        lane: 'upstream_haxe',
        values: upstreamValues
      })
    }
    if (hxhxValues) {
      samples.push({
        metric,
        lane: 'hxhx',
        values: hxhxValues
      })
    }
  }

  const evidence = {
    schema: 'full1-perf-evidence.v1',
    haxeCompatibilityBaseline: '4.3.7',
    runner: {
      source: 'scripts/hxhx/bench-kpi.sh',
      inputSchema: 'hxhx.kpi.v1',
      inputPath: parsed.kpiReport,
      hxhxLane: parsed.hxhxLane,
      missingSamples: missing
    },
    git: gitMetadata(),
    workloads: [
      {
        id: 'full1-kpi-compile-and-macro',
        samples
      }
    ]
  }

  fs.mkdirSync(path.dirname(parsed.jsonOut), { recursive: true })
  fs.writeFileSync(parsed.jsonOut, JSON.stringify(evidence, null, 2) + '\n')
  if (missing.length > 0) {
    console.error(`[full1-kpi-evidence] WARNING: missing KPI samples: ${missing.join(', ')}`)
  }
  console.log(`[full1-kpi-evidence] evidence=${parsed.jsonOut}`)
}

main()
