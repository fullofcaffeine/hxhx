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
const knownSignaturesPath = 'packages/hxhx-core/src/backend/cpp/CppKnownStdlibSignatures.hx'
const traceContextPath = 'packages/hxhx-core/src/backend/cpp/CppTraceContext.hx'

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

function requireCount(filePath, text, snippet, expected) {
  const count = text.split(snippet).length - 1
  if (count !== expected) {
    fail(`${filePath} must include ${JSON.stringify(snippet)} exactly ${expected} time(s), found ${count}`)
  }
}

function main() {
  const plan = readText(planPath)
  const docsReadme = readText(docsReadmePath)
  const packageJson = readText(packageJsonPath)
  const cppCore = readText(cppCorePath)
  const knownSignatures = readText(knownSignaturesPath)
  const traceContext = readText(traceContextPath)

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
    'traceCppDeepEnabled(context:CppTraceContext)',
    'traceCppLambdaPhasesEnabled(context:CppTraceContext)',
    'traceCppCallArgDetailPhasesEnabled(context:CppTraceContext)',
    'traceCppHelperClassificationDetailsEnabled(context:CppTraceContext)',
    'traceCppScopeStmtTimingPhase',
    'render_helper_method_prepare_timing',
    'field_infer_',
    '"known"',
    '"receiver_type"',
    'functionAnalysisMemo',
    'functionAnalysisMemoForLookup',
    'traceContextForLookup',
    'scope.traceContext',
    'knownStdlibSignatures().methodReturnCppType',
    'knownStdlibSignatures().methodParamCppTypes',
  ]) {
    requireIncludes(cppCorePath, cppCore, snippet)
  }
  for (const staleProcessField of [
    'traceCppTimingsEnabledCache',
    'traceCppTimingMethodFilterCache',
    'traceCppTimingPhaseBuffer',
    'traceCppDeepEnabledCache',
    'traceCppLambdaPhasesEnabledCache',
    'traceCppCallArgDetailPhasesEnabledCache',
    'traceCppHelperClassificationDetailsEnabledCache',
  ]) {
    if (cppCore.includes(staleProcessField)) {
      fail(`${cppCorePath} must not retain program timing state in process field ${staleProcessField}`)
    }
  }
  if (cppCore.includes('function resetRequestState')) {
    fail(`${cppCorePath} must not restore a C++ request-reset lifecycle after all mutable program state moved to program-owned contexts`)
  }
  requireCount(cppCorePath, cppCore, '{names: scope.classNames, byName: scope.classByName, all: scope.allClasses}', 1)

  for (const snippet of [
    'class CppTraceContext',
    'public final timingsEnabled',
    'public final timingMethodFilter',
    'public final deepEnabled',
    'public final lambdaPhasesEnabled',
    'public final callArgDetailPhasesEnabled',
    'public final helperClassificationDetailsEnabled',
    'public var timingPhaseBuffer',
  ]) {
    requireIncludes(traceContextPath, traceContext, snippet)
  }

  for (const snippet of [
    'class CppKnownStdlibSignatures',
    'does not select Haxe declarations',
    'public function methodReturnCppType',
    'public function methodParamCppTypes',
    'public function preludeMethodReturnType',
    'public function preludeMethodParamTypes',
  ]) {
    requireIncludes(knownSignaturesPath, knownSignatures, snippet)
  }

  requireIncludes(docsReadmePath, docsReadme, 'CPP_RENDER_TYPE_FLOW_PLAN.md')
  requireIncludes(packageJsonPath, packageJson, 'guard:cpp-render-type-flow-plan')
  requireIncludes(packageJsonPath, packageJson, 'test:m14:cpp-strict-frontier-summary')

  if (process.exitCode) return
  console.log('[ci:guards] OK: Cpp render/type-flow plan is wired to timing diagnostics')
  console.log('CPP_RENDER_TYPE_FLOW_PLAN:PASS')
}

main()
