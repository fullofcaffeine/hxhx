#!/usr/bin/env node
/**
 * Guard the Full1 suite workflow's macro runtime split.
 *
 * The suite runner script defaults to in-process macro execution. This workflow
 * must not accidentally force every suite back through the external macro host,
 * because that hides inproc parity gaps and serializes cheap suite lanes behind
 * the macro-host build.
 */

const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const workflowPath = path.join(root, '.github/workflows/full1-suite-runners.yml')
const workflow = fs.readFileSync(workflowPath, 'utf8')

function fail(message) {
  console.error(`[full1-suite-workflow-runtime-check] ${message}`)
  process.exit(1)
}

function jobSection(name) {
  const startMarker = `\n  ${name}:\n`
  const start = workflow.indexOf(startMarker)
  if (start < 0) {
    fail(`missing job ${name}`)
  }
  const rest = workflow.slice(start + startMarker.length)
  const next = rest.search(/\n  [A-Za-z0-9_-]+:\n/)
  return next < 0 ? rest : rest.slice(0, next)
}

function requireContains(sectionName, section, needle) {
  if (!section.includes(needle)) {
    fail(`${sectionName} must contain ${needle}`)
  }
}

function requireNotContains(sectionName, section, needle) {
  if (section.includes(needle)) {
    fail(`${sectionName} must not contain ${needle}`)
  }
}

const buildHxhx = jobSection('build_hxhx')
const buildMacroHost = jobSection('build_macro_host')
const inprocRunner = jobSection('full1_suite_runner_inproc')
const externalRunner = jobSection('full1_suite_runner_external_host')

requireContains('build_hxhx', buildHxhx, 'build_one "scripts/hxhx/build-hxhx.sh"')
requireNotContains('build_hxhx', buildHxhx, 'build-hxhx-macro-host.sh')

requireContains('build_macro_host', buildMacroHost, 'bash scripts/hxhx/build-hxhx-macro-host.sh')
requireContains('build_macro_host', buildMacroHost, 'name: full1-suite-macro-host-${{ github.run_id }}')

requireContains('full1_suite_runner_inproc', inprocRunner, 'suite: [misc, threads, display]')
requireContains('full1_suite_runner_inproc', inprocRunner, 'export HXHX_MACRO_RUNTIME_MODE=inproc')
requireContains('full1_suite_runner_inproc', inprocRunner, 'unset HXHX_MACRO_HOST_EXE')
requireNotContains('full1_suite_runner_inproc', inprocRunner, 'full1-suite-macro-host-${{ github.run_id }}')
requireNotContains('full1_suite_runner_inproc', inprocRunner, 'chmod +x "${{ env.FULL1_SUITE_ARTIFACTS_DIR }}/hxhx-macro-host"')

requireContains('full1_suite_runner_external_host', externalRunner, 'needs: [build_hxhx, build_macro_host]')
requireContains('full1_suite_runner_external_host', externalRunner, 'suite: [server, optimization]')
requireContains('full1_suite_runner_external_host', externalRunner, 'name: full1-suite-macro-host-${{ github.run_id }}')
requireContains('full1_suite_runner_external_host', externalRunner, 'export HXHX_MACRO_RUNTIME_MODE=external-host')
requireContains('full1_suite_runner_external_host', externalRunner, 'export HXHX_MACRO_HOST_EXE="${{ env.FULL1_SUITE_ARTIFACTS_DIR }}/hxhx-macro-host"')

console.log('[full1-suite-workflow-runtime-check] ok')
