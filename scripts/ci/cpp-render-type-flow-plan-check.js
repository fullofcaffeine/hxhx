#!/usr/bin/env node
/**
 * Guard the Cpp render/type-flow extraction plan.
 *
 * This check keeps the architecture note wired to existing timing diagnostics
 * and focused smoke validation. It does not execute performance workloads.
 */

const fs = require('fs')

const planPath = 'docs/00-project/CPP_RENDER_TYPE_FLOW_PLAN.md'
const docsReadmePath = 'docs/README.md'
const packageJsonPath = 'package.json'
const cppCorePath = 'packages/hxhx-core/src/backend/cpp/CppTargetCore.hx'

function fail(message) {
  console.error(`[cpp-render-type-flow-plan-check] ERROR: ${message}`)
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

function main() {
  const plan = readText(planPath)
  const docsReadme = readText(docsReadmePath)
  const packageJson = readText(packageJsonPath)
  const cppCore = readText(cppCorePath)

  for (const snippet of [
    'CPP_RENDER_TYPE_FLOW_PLAN:PASS',
    'haxe_ocaml-36ec',
    'CppFieldCallPlan',
    'CppCallResolution',
    'HXHX_TRACE_STAGE3_CPP_TIMINGS',
    'HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER',
    'render_helper_method_prepare_timing',
    'field_infer_known',
    'field_infer_receiver_type',
    'cpp-strict-frontier-summary.js',
    'CPP_STRICT_FRONTIER_SUMMARY',
    'npm run test:m14:cpp-native-backend-smoke',
    'npm run test:m14:cpp-strict-frontier-summary',
    'README/North Star progress bars recorded as unchanged',
  ]) {
    requireIncludes(planPath, plan, snippet)
  }

  for (const snippet of [
    'traceCppTimingsEnabled',
    'traceCppScopeStmtTimingPhase',
    'render_helper_method_prepare_timing',
    'field_infer_',
    '"known"',
    '"receiver_type"',
    'functionScopePrepCache',
    'functionArgTypesCache',
    'functionReturnTypesCache',
  ]) {
    requireIncludes(cppCorePath, cppCore, snippet)
  }

  requireIncludes(docsReadmePath, docsReadme, 'CPP_RENDER_TYPE_FLOW_PLAN.md')
  requireIncludes(packageJsonPath, packageJson, 'guard:cpp-render-type-flow-plan')
  requireIncludes(packageJsonPath, packageJson, 'test:m14:cpp-strict-frontier-summary')

  if (process.exitCode) return
  console.log('[ci:guards] OK: Cpp render/type-flow plan is wired to timing diagnostics')
  console.log('CPP_RENDER_TYPE_FLOW_PLAN:PASS')
}

main()
