#!/usr/bin/env node
/**
 * Guard Full1 phase timing workflow wiring.
 *
 * The timing helper has fixture coverage for record shape; this guard checks
 * that heavy Full1 workflows keep publishing the expected timing artifacts.
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

const suiteWorkflow = read(suiteWorkflowPath)
const perfWorkflow = read(perfWorkflowPath)
const evalWorkflow = read(evalWorkflowPath)
const pluginWorkflow = read(pluginWorkflowPath)

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

console.log('[full1-phase-timing-workflow-check] ok')
