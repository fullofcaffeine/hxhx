#!/usr/bin/env node
/**
 * Guard the native iteration latency north-star contract.
 *
 * This check validates the measurement contract and its references. It does not
 * execute performance workloads or claim that latency targets have been met.
 */

const fs = require('fs')

const contractPath = 'docs/00-project/NATIVE_ITERATION_LATENCY_CONTRACT.md'
const northStarPath = 'docs/00-project/NORTH_STAR_GOALS.md'
const ciGatesPath = 'docs/00-project/CI_GATES.md'
const readmePath = 'README.md'
const packageJsonPath = 'package.json'
const kpiWorkflowPath = '.github/workflows/hxhx-kpi-report.yml'
const bootstrapWorkflowPath = '.github/workflows/bootstrap-regen-bench.yml'
const artifactComparisonRunnerPath = 'scripts/hxhx/bench-kpi-artifact-comparison.sh'

function fail(message) {
  console.error(`[native-iteration-latency-contract-check] ERROR: ${message}`)
  process.exitCode = 1
}

function readText(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`missing required file: ${filePath}`)
    return ''
  }
  return fs.readFileSync(filePath, 'utf8')
}

function requireIncludes(filePath, text, snippet) {
  if (!text.includes(snippet)) {
    fail(`${filePath} must include: ${snippet}`)
  }
}

function extractPolicyJson(doc) {
  const match = doc.match(
    /<!-- NATIVE_ITERATION_LATENCY_POLICY_JSON_START -->\s*```json\s*([\s\S]*?)\s*```\s*<!-- NATIVE_ITERATION_LATENCY_POLICY_JSON_END -->/
  )
  if (!match) {
    fail(`${contractPath} must include NATIVE_ITERATION_LATENCY_POLICY_JSON_START/END markers`)
    return null
  }
  try {
    return JSON.parse(match[1])
  } catch (error) {
    fail(`${contractPath} policy JSON is invalid: ${error.message}`)
    return null
  }
}

function checkEvidence(bucket) {
  if (!Array.isArray(bucket.evidence) || bucket.evidence.length === 0) {
    fail(`bucket ${bucket.id} must define evidence[]`)
    return
  }
  for (const evidencePath of bucket.evidence) {
    if (!fs.existsSync(evidencePath)) {
      fail(`bucket ${bucket.id} references missing evidence path: ${evidencePath}`)
    }
  }
}

function main() {
  const contract = readText(contractPath)
  const northStar = readText(northStarPath)
  const ciGates = readText(ciGatesPath)
  const readme = readText(readmePath)
  const packageJson = readText(packageJsonPath)
  const kpiWorkflow = readText(kpiWorkflowPath)
  const bootstrapWorkflow = readText(bootstrapWorkflowPath)
  const artifactComparisonRunner = readText(artifactComparisonRunnerPath)

  for (const snippet of [
    'NATIVE_ITERATION_LATENCY_POLICY:PASS',
    'haxe.ocaml-5rjl',
    'haxe_ocaml-850ii',
    'scripts/ci/full1-phase-timing.js',
    'scripts/ci/m7-shared-artifacts.js',
    'scripts/ci/hxhx-kpi-report-validator.js',
    'scripts/ci/hxhx-kpi-artifact-comparison.js',
    'scripts/ci/bootstrap-regen-benchmark-report.js',
    'scripts/hxhx/bench-bootstrap-regen.sh',
    'scripts/ci/stage0-free-build-benchmark-report.js',
    'scripts/hxhx/bench-stage0-free-build.sh',
    'scripts/ci/native-plugin-loop-benchmark-report.js',
    'scripts/hxhx/bench-native-plugin-loop.sh',
    'scripts/hxhx/bench-native-reflaxe.sh',
    'FULL1_PERF_PARITY:PASS',
    'README `Goals status` table'
  ]) {
    requireIncludes(contractPath, contract, snippet)
  }

  requireIncludes(northStarPath, northStar, contractPath)
  requireIncludes(ciGatesPath, ciGates, contractPath)
  requireIncludes(readmePath, readme, 'practical edit-compile-test latency')
  requireIncludes(packageJsonPath, packageJson, 'native-iteration-latency-contract-check.js')
  requireIncludes(packageJsonPath, packageJson, 'hxhx-kpi-artifact-comparison-fixture-test.js')
  requireIncludes(packageJsonPath, packageJson, 'native-plugin-loop-benchmark-report-fixture-test.js')
  requireIncludes(packageJsonPath, packageJson, 'stage0-free-build-benchmark-report-fixture-test.js')
  for (const snippet of [
    'compare_native:',
    'scripts/hxhx/bench-kpi-artifact-comparison.sh',
    'hxhx-kpi-bytecode-native-${{ github.run_id }}'
  ]) {
    requireIncludes(kpiWorkflowPath, kpiWorkflow, snippet)
  }
  const stage0PolicyInput = bootstrapWorkflow.match(
    /\n      stage0_policy:\n([\s\S]*?)(?=\n      [a-zA-Z0-9_]+:|\n\n)/
  )
  if (!stage0PolicyInput) {
    fail(`${bootstrapWorkflowPath} must define the stage0_policy workflow input`)
  } else {
    requireIncludes(bootstrapWorkflowPath, stage0PolicyInput[1], 'required: false')
    requireIncludes(bootstrapWorkflowPath, stage0PolicyInput[1], 'default: ""')
  }
  for (const snippet of [
    'HXHX_BOOTSTRAP_PREFER_NATIVE=1',
    'HXHX_STAGE0_OCAML_BUILD=native',
    'scripts/ci/hxhx-kpi-report-validator.js',
    'scripts/ci/hxhx-kpi-artifact-comparison.js'
  ]) {
    requireIncludes(artifactComparisonRunnerPath, artifactComparisonRunner, snippet)
  }

  const policy = extractPolicyJson(contract)
  if (!policy) return

  if (policy.schema !== 'native-iteration-latency-policy.v1') {
    fail(`unexpected policy schema: ${policy.schema}`)
  }
  if (policy.contractMarker !== 'NATIVE_ITERATION_LATENCY_POLICY:PASS') {
    fail(`unexpected contract marker: ${policy.contractMarker}`)
  }
  if (policy.haxeCompatibilityBaseline !== '4.3.7') {
    fail(`policy baseline must be 4.3.7, received ${policy.haxeCompatibilityBaseline}`)
  }
  if (policy.primaryOwnerBead !== 'haxe_ocaml-850ii') {
    fail('policy.primaryOwnerBead must point at active successor haxe_ocaml-850ii')
  }
  if (policy.completedFoundationBead !== 'haxe.ocaml-5rjl') {
    fail('policy.completedFoundationBead must preserve haxe.ocaml-5rjl')
  }
  if (!policy.timingTool || !fs.existsSync(policy.timingTool)) {
    fail(`policy.timingTool references missing path: ${policy.timingTool}`)
  }
  if (!policy.policyGuard || policy.policyGuard !== 'scripts/ci/native-iteration-latency-contract-check.js') {
    fail('policy.policyGuard must point at scripts/ci/native-iteration-latency-contract-check.js')
  }
  if (!policy.activeEvidenceLoop || typeof policy.activeEvidenceLoop !== 'object') {
    fail('policy.activeEvidenceLoop must describe the current KPI evidence path')
  } else {
    if (policy.activeEvidenceLoop.full1PhaseTimingReportSchema !== 'full1-phase-timing-summary.v2') {
      fail('policy.activeEvidenceLoop.full1PhaseTimingReportSchema must be full1-phase-timing-summary.v2')
    }
    if (policy.activeEvidenceLoop.m7SharedArtifactReceiptSchema !== 'm7-shared-artifacts.v1') {
      fail('policy.activeEvidenceLoop.m7SharedArtifactReceiptSchema must be m7-shared-artifacts.v1')
    }
    if (policy.activeEvidenceLoop.reportSchema !== 'hxhx.kpi.v2') {
      fail('policy.activeEvidenceLoop.reportSchema must be hxhx.kpi.v2')
    }
    if (policy.activeEvidenceLoop.artifactComparisonSchema !== 'hxhx.kpi-artifact-comparison.v1') {
      fail('policy.activeEvidenceLoop.artifactComparisonSchema must be hxhx.kpi-artifact-comparison.v1')
    }
    if (policy.activeEvidenceLoop.bootstrapReportSchema !== 'hxhx.bootstrap-regen-benchmark.v1') {
      fail('policy.activeEvidenceLoop.bootstrapReportSchema must be hxhx.bootstrap-regen-benchmark.v1')
    }
    if (policy.activeEvidenceLoop.nativePluginLoopReportSchema !== 'hxhx.native-plugin-loop.v1') {
      fail('policy.activeEvidenceLoop.nativePluginLoopReportSchema must be hxhx.native-plugin-loop.v1')
    }
    if (policy.activeEvidenceLoop.stage0FreeBuildReportSchema !== 'hxhx.stage0-free-build.v1') {
      fail('policy.activeEvidenceLoop.stage0FreeBuildReportSchema must be hxhx.stage0-free-build.v1')
    }
    for (const field of [
      'full1PhaseTimingReportValidator',
      'm7SharedArtifactReceiptValidator',
      'm7SharedArtifactRunner',
      'reportValidator',
      'reportWorkflow',
      'artifactComparisonValidator',
      'artifactComparisonRunner',
      'bootstrapReportValidator',
      'bootstrapReportWorkflow',
      'stage0FreeBuildReportValidator',
      'stage0FreeBuildReportRunner',
      'nativePluginLoopReportValidator',
      'nativePluginLoopReportRunner'
    ]) {
      const evidencePath = policy.activeEvidenceLoop[field]
      if (!evidencePath || !fs.existsSync(evidencePath)) {
        fail(`policy.activeEvidenceLoop.${field} references missing path: ${evidencePath}`)
      }
    }
  }
  if (!Array.isArray(policy.measurementBuckets) || policy.measurementBuckets.length < 5) {
    fail('policy.measurementBuckets must define at least five buckets')
  } else {
    const requiredIds = new Set([
      'focused-local-smoke',
      'bootstrap-snapshot-regeneration',
      'stage0-free-hxhx-rebuild',
      'native-reflaxe-artifact-loop',
      'full1-evidence-gates',
    ])
    const seen = new Set()
    for (const bucket of policy.measurementBuckets) {
      if (!bucket.id || !bucket.purpose || !bucket.target) {
        fail('each measurement bucket must include id, purpose, and target')
        continue
      }
      seen.add(bucket.id)
      checkEvidence(bucket)
    }
    for (const id of requiredIds) {
      if (!seen.has(id)) fail(`missing required measurement bucket: ${id}`)
    }
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: native iteration latency contract is valid')
  console.log('NATIVE_ITERATION_LATENCY_POLICY:PASS')
}

main()
