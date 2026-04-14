#!/usr/bin/env node
/**
 * Evaluate Full1 performance evidence against the policy contract.
 *
 * Input schema: full1-perf-evidence.v1
 * Output schema: full1-perf-evaluation.v1
 */

const fs = require('fs')
const path = require('path')

const defaultPolicyDoc = 'docs/00-project/FULL1_PERF_PARITY_POLICY.md'

function usage() {
  console.error(`Usage: node scripts/ci/full1-perf-evaluator.js --evidence <summary.json> --json-out <evaluation.json>

Options:
  --policy-doc <path>  Policy markdown with FULL1_PERF_POLICY_JSON block
  --evidence <path>    Evidence JSON file, repeatable
  --json-out <path>    Evaluation summary output path
`)
}

function fail(message, code = 2) {
  console.error(`[full1-perf-evaluator] ERROR: ${message}`)
  process.exit(code)
}

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function readJson(filePath) {
  return JSON.parse(readUtf8(filePath))
}

function parseArgs(argv) {
  const parsed = {
    policyDoc: defaultPolicyDoc,
    evidence: [],
    jsonOut: null
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--policy-doc') {
      i += 1
      if (i >= argv.length) fail('missing value for --policy-doc')
      parsed.policyDoc = argv[i]
    } else if (arg === '--evidence') {
      i += 1
      if (i >= argv.length) fail('missing value for --evidence')
      parsed.evidence.push(argv[i])
    } else if (arg === '--json-out') {
      i += 1
      if (i >= argv.length) fail('missing value for --json-out')
      parsed.jsonOut = argv[i]
    } else if (arg === '--help' || arg === '-h') {
      usage()
      process.exit(0)
    } else {
      fail(`unknown argument: ${arg}`)
    }
  }
  if (parsed.evidence.length === 0) fail('at least one --evidence file is required')
  if (!parsed.jsonOut) fail('--json-out is required')
  return parsed
}

function loadPolicy(policyDocPath) {
  const text = readUtf8(policyDocPath)
  const match = text.match(
    /<!-- FULL1_PERF_POLICY_JSON_START -->\s*```json\s*([\s\S]*?)\s*```\s*<!-- FULL1_PERF_POLICY_JSON_END -->/
  )
  if (!match) fail(`missing policy JSON block in ${policyDocPath}`)
  const policy = JSON.parse(match[1])
  if (policy.schema !== 'full1-perf-policy.v1') fail(`unexpected policy schema: ${policy.schema}`)
  return policy
}

function median(values) {
  if (!Array.isArray(values) || values.length === 0) return null
  const sorted = values.map(Number).filter(Number.isFinite).sort((a, b) => a - b)
  if (sorted.length === 0) return null
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

function mean(values) {
  if (!Array.isArray(values) || values.length === 0) return null
  const nums = values.map(Number).filter(Number.isFinite)
  if (nums.length === 0) return null
  return nums.reduce((a, b) => a + b, 0) / nums.length
}

function coefficientOfVariationPct(values) {
  const nums = values.map(Number).filter(Number.isFinite)
  if (nums.length <= 1) return 0
  const avg = mean(nums)
  if (!avg || avg <= 0) return null
  const variance = nums.reduce((sum, value) => sum + Math.pow(value - avg, 2), 0) / nums.length
  return (Math.sqrt(variance) / avg) * 100
}

function round(value) {
  if (value === null || value === undefined || !Number.isFinite(value)) return null
  return Number(value.toFixed(6))
}

function sampleFor(workload, metric, lane) {
  const samples = Array.isArray(workload.samples) ? workload.samples : []
  return samples.find(sample => sample.metric === metric && sample.lane === lane) || null
}

function metricNames(workload) {
  const seen = new Set()
  for (const sample of Array.isArray(workload.samples) ? workload.samples : []) {
    if (sample && typeof sample.metric === 'string' && sample.metric.length > 0) seen.add(sample.metric)
  }
  return Array.from(seen).sort()
}

function hardCeilingForMetric(policy, metric) {
  if (metric === 'peak_rss_kb' || metric === 'peak_rss_mb') return policy.thresholds.rssHardCeilingRatio
  return policy.thresholds.requiredWorkloadHardCeilingRatio
}

function allowsNearZeroDeltaNoise(policy, metric, upstreamMedian, hxhxMedian) {
  const noise = policy.noise || {}
  const metrics = Array.isArray(noise.nearZeroDeltaMetrics) ? noise.nearZeroDeltaMetrics : []
  if (!metrics.includes(metric)) return false
  const maxMedianMs = Number(noise.nearZeroDeltaMetricsMaxMedianMs)
  if (!Number.isFinite(maxMedianMs) || maxMedianMs < 0) return false
  if (hxhxMedian === null || upstreamMedian === null) return false
  return hxhxMedian <= maxMedianMs && hxhxMedian <= upstreamMedian
}

function evaluateMetric(policy, workload, metric) {
  const upstream = sampleFor(workload, metric, 'upstream_haxe')
  const hxhx = sampleFor(workload, metric, 'hxhx')
  const failures = []

  if (!upstream) failures.push(`missing upstream_haxe samples for ${metric}`)
  if (!hxhx) failures.push(`missing hxhx samples for ${metric}`)
  if (failures.length > 0) {
    return { metric, decision: 'fail', failures }
  }

  const upstreamValues = Array.isArray(upstream.values) ? upstream.values.map(Number).filter(Number.isFinite) : []
  const hxhxValues = Array.isArray(hxhx.values) ? hxhx.values.map(Number).filter(Number.isFinite) : []
  if (upstreamValues.length < policy.noise.measuredRepetitions) {
    failures.push(`upstream_haxe ${metric} needs at least ${policy.noise.measuredRepetitions} samples`)
  }
  if (hxhxValues.length < policy.noise.measuredRepetitions) {
    failures.push(`hxhx ${metric} needs at least ${policy.noise.measuredRepetitions} samples`)
  }

  const upstreamMedian = median(upstreamValues)
  const hxhxMedian = median(hxhxValues)
  if (upstreamMedian === null || upstreamMedian <= 0) failures.push(`upstream_haxe ${metric} median must be positive`)
  if (hxhxMedian === null || hxhxMedian < 0) failures.push(`hxhx ${metric} median must be non-negative`)

  const upstreamCv = coefficientOfVariationPct(upstreamValues)
  const hxhxCv = coefficientOfVariationPct(hxhxValues)
  const maxCv = Math.max(upstreamCv || 0, hxhxCv || 0)
  if (
    maxCv > policy.noise.maxCoefficientOfVariationPct
    && !allowsNearZeroDeltaNoise(policy, metric, upstreamMedian, hxhxMedian)
  ) {
    failures.push(`${metric} is noisy: max coefficient of variation ${round(maxCv)}% exceeds ${policy.noise.maxCoefficientOfVariationPct}%`)
  }

  const ratio = upstreamMedian && hxhxMedian !== null ? hxhxMedian / upstreamMedian : null
  const hardCeiling = hardCeilingForMetric(policy, metric)
  if (ratio !== null && ratio > hardCeiling) {
    failures.push(`${metric} ratio ${round(ratio)} exceeds hard ceiling ${hardCeiling}`)
  }

  return {
    metric,
    decision: failures.length === 0 ? 'pass' : 'fail',
    upstreamMedian: round(upstreamMedian),
    hxhxMedian: round(hxhxMedian),
    ratio: round(ratio),
    upstreamCoefficientOfVariationPct: round(upstreamCv),
    hxhxCoefficientOfVariationPct: round(hxhxCv),
    hardCeiling,
    failures
  }
}

function evaluateWorkload(policy, workload) {
  const failures = []
  if (!workload || typeof workload.id !== 'string' || workload.id.length === 0) {
    failures.push('workload must include id')
  }
  if (workload && Array.isArray(workload.failures)) {
    for (const failure of workload.failures) {
      if (typeof failure === 'string' && failure.length > 0) failures.push(failure)
    }
  }
  const metrics = metricNames(workload)
  if (metrics.length === 0) failures.push('workload must include metric samples')

  const metricResults = metrics.map(metric => evaluateMetric(policy, workload, metric))
  for (const result of metricResults) {
    for (const failure of result.failures || []) failures.push(failure)
  }

  const ratios = metricResults.map(result => result.ratio).filter(value => value !== null)
  const categoryMedianRatio = median(ratios)
  if (categoryMedianRatio !== null && categoryMedianRatio > policy.thresholds.requiredCategoryMedianMaxRatio) {
    failures.push(
      `category median ratio ${round(categoryMedianRatio)} exceeds ${policy.thresholds.requiredCategoryMedianMaxRatio}`
    )
  }

  return {
    id: workload && workload.id ? workload.id : '<missing-id>',
    decision: failures.length === 0 ? 'pass' : 'fail',
    categoryMedianRatio: round(categoryMedianRatio),
    metrics: metricResults,
    failures
  }
}

function evaluateEvidence(policy, evidence, sourcePath) {
  const failures = []
  if (!evidence || evidence.schema !== 'full1-perf-evidence.v1') {
    failures.push(`unexpected evidence schema in ${sourcePath}: ${evidence && evidence.schema}`)
  }
  if (evidence && evidence.haxeCompatibilityBaseline !== policy.haxeCompatibilityBaseline) {
    failures.push(`baseline mismatch in ${sourcePath}: ${evidence.haxeCompatibilityBaseline}`)
  }
  const workloads = evidence && Array.isArray(evidence.workloads) ? evidence.workloads : []
  if (workloads.length === 0) failures.push(`no workloads in ${sourcePath}`)
  const workloadResults = workloads.map(workload => evaluateWorkload(policy, workload))
  for (const result of workloadResults) {
    for (const failure of result.failures || []) failures.push(`${result.id}: ${failure}`)
  }
  return {
    sourcePath,
    decision: failures.length === 0 ? 'pass' : 'fail',
    workloads: workloadResults,
    failures
  }
}

function evaluateRequiredCoverage(policy, evidenceResults) {
  const failures = []
  const workloadResultsById = new Map()
  for (const evidenceResult of evidenceResults) {
    for (const workloadResult of evidenceResult.workloads || []) {
      if (workloadResultsById.has(workloadResult.id)) {
        failures.push(`duplicate workload evidence for ${workloadResult.id}`)
        continue
      }
      workloadResultsById.set(workloadResult.id, workloadResult)
    }
  }

  for (const workloadSpec of Array.isArray(policy.workloads) ? policy.workloads : []) {
    const id = workloadSpec.id
    const workloadResult = workloadResultsById.get(id)
    if (!workloadResult) {
      failures.push(`missing required workload ${id}`)
      continue
    }

    const seenMetrics = new Set((workloadResult.metrics || []).map(result => result.metric))
    for (const metric of Array.isArray(workloadSpec.requiredMetrics) ? workloadSpec.requiredMetrics : []) {
      if (!seenMetrics.has(metric)) failures.push(`${id}: missing required metric ${metric}`)
    }
  }

  return failures
}

function main() {
  const parsed = parseArgs(process.argv.slice(2))
  const policy = loadPolicy(parsed.policyDoc)
  const evidenceResults = parsed.evidence.map(filePath => evaluateEvidence(policy, readJson(filePath), filePath))
  const failures = []
  for (const result of evidenceResults) {
    for (const failure of result.failures || []) failures.push(failure)
  }
  for (const failure of evaluateRequiredCoverage(policy, evidenceResults)) failures.push(failure)
  const decision = failures.length === 0 ? 'pass' : 'fail'
  const summary = {
    schema: 'full1-perf-evaluation.v1',
    marker: decision === 'pass' ? policy.evidenceMarker : null,
    policyMarker: policy.contractMarker,
    haxeCompatibilityBaseline: policy.haxeCompatibilityBaseline,
    decision,
    evidence: evidenceResults,
    thresholds: policy.thresholds,
    noise: policy.noise,
    failures
  }

  fs.mkdirSync(path.dirname(parsed.jsonOut), { recursive: true })
  fs.writeFileSync(parsed.jsonOut, JSON.stringify(summary, null, 2) + '\n')
  console.log(`[full1-perf-evaluator] summary=${parsed.jsonOut}`)
  console.log(`[full1-perf-evaluator] decision=${decision}`)
  if (decision === 'pass') {
    console.log(policy.evidenceMarker)
    return
  }
  process.exit(1)
}

main()
