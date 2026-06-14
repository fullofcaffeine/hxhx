#!/usr/bin/env node
/**
 * Guard Full1 phase timing workflow wiring.
 *
 * The timing helper has fixture coverage for record shape; this guard checks
 * that heavy Full1 workflows keep publishing the expected timing artifacts and
 * keep the benchmark-backed OCaml/dune worker/cache policy explicit.
 */

const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '../..')

function fail(message) {
  console.error(`[full1-phase-timing-workflow-check] ${message}`)
  process.exit(1)
}

function read(relPath) {
  return fs.readFileSync(path.join(root, relPath), 'utf8')
}

function requireIncludes(relPath, haystack, needle) {
  if (!haystack.includes(needle)) {
    fail(`${relPath} missing required timing wiring: ${needle}`)
  }
}

const suiteWorkflowPath = '.github/workflows/full1-suite-runners.yml'
const perfWorkflowPath = '.github/workflows/gate-perf-full1.yml'
const evalWorkflowPath = '.github/workflows/full1-eval-native.yml'
const pluginWorkflowPath = '.github/workflows/full1-plugin-parity.yml'
const macroWorkflowPath = '.github/workflows/macro-runtime-parity-weekly.yml'
const gate3WorkflowPath = '.github/workflows/gate3-full1-extended.yml'
const sourceProbeWorkflowPath = '.github/workflows/full1-source-probe.yml'
const reconcileWorkflowPath = '.github/workflows/full1-bootstrap-source-reconcile.yml'

const suiteWorkflow = read(suiteWorkflowPath)
const perfWorkflow = read(perfWorkflowPath)
const evalWorkflow = read(evalWorkflowPath)
const pluginWorkflow = read(pluginWorkflowPath)
const macroWorkflow = read(macroWorkflowPath)
const gate3Workflow = read(gate3WorkflowPath)
const sourceProbeWorkflow = read(sourceProbeWorkflowPath)
const reconcileWorkflow = read(reconcileWorkflowPath)

for (const needle of [
  'build_hxhx.timings.jsonl',
  'build_macro_host.timings.jsonl',
  '${{ matrix.suite }}.timings.jsonl',
  'Summarize Full1 suite timings',
]) {
  requireIncludes(suiteWorkflowPath, suiteWorkflow, needle)
}

for (const needle of [
  'full1-perf.timings.jsonl',
  'build_hxhx_binary',
  'build_macro_host_binary',
  'perf_evaluator',
]) {
  requireIncludes(perfWorkflowPath, perfWorkflow, needle)
}

for (const needle of [
  'FULL1_EVAL_NATIVE_TIMINGS_JSONL',
  'full1-eval-native.timings.jsonl',
  'install_host_toolchains',
  'build_hxhx_binary',
  'native_eval_runner',
  'Summarize Full1 eval native timings',
]) {
  requireIncludes(evalWorkflowPath, evalWorkflow, needle)
}

for (const needle of [
  '${{ matrix.id }}.timings.jsonl',
  'install_ocaml_packages',
  'prepare_upstream_eval_host',
  'plugin_proof',
  'Summarize ${{ matrix.name }} timings',
]) {
  requireIncludes(pluginWorkflowPath, pluginWorkflow, needle)
}

for (const needle of [
  'HXHX_PARITY_TIMINGS_JSONL',
  '${{ matrix.macro_runtime_mode }}.timings.jsonl',
  'build_hxhx_binary',
  'unit_macro_stage3_no_emit',
  'runci_macro_stage3_no_emit',
  'display_macro_protocol',
  'Summarize macro runtime parity timings',
]) {
  requireIncludes(macroWorkflowPath, macroWorkflow, needle)
}

for (const needle of [
  'FULL1_GATE3_EXTENDED_TIMINGS_JSONL',
  'FULL1_GATE3_EXTENDED_MATRIX_TIMEOUT_SEC',
  'gate3-full1-extended.timings.jsonl',
  'install_host_toolchains',
  'strict_extended_gate3_matrix',
  'timeout --foreground "${FULL1_GATE3_EXTENDED_MATRIX_TIMEOUT_SEC}s"',
  'Summarize Full1 Gate3 extended timings',
]) {
  requireIncludes(gate3WorkflowPath, gate3Workflow, needle)
}

for (const [relPath, workflow] of [
  [suiteWorkflowPath, suiteWorkflow],
  [perfWorkflowPath, perfWorkflow],
  [evalWorkflowPath, evalWorkflow],
  [pluginWorkflowPath, pluginWorkflow],
  [macroWorkflowPath, macroWorkflow],
  [gate3WorkflowPath, gate3Workflow],
  [sourceProbeWorkflowPath, sourceProbeWorkflow],
  [reconcileWorkflowPath, reconcileWorkflow],
]) {
  requireIncludes(relPath, workflow, 'HXHX_DUNE_JOBS:')
  if (!workflow.includes('HXHX_DUNE_JOBS: "auto"') && !workflow.includes("HXHX_DUNE_JOBS: 'auto'")) {
    fail(`${relPath} must keep benchmark-backed HXHX_DUNE_JOBS=auto explicit`)
  }
}

for (const [relPath, workflow] of [
  [perfWorkflowPath, perfWorkflow],
  [pluginWorkflowPath, pluginWorkflow],
]) {
  requireIncludes(relPath, workflow, 'uses: ocaml/setup-ocaml@v3')
  requireIncludes(relPath, workflow, 'dune-cache: true')
}

console.log('[full1-phase-timing-workflow-check] ok')
