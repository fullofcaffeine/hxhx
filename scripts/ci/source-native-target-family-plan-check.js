#!/usr/bin/env node
/**
 * Guard the source-native target-family extraction plan.
 *
 * This check keeps the architecture plan wired to the current target facade,
 * delegated target-core seams, runtime-template inventory, docs index, and
 * package guard script. It does not execute source-native target workloads.
 */

const fs = require('fs')

const planPath = 'docs/00-project/SOURCE_NATIVE_TARGET_FAMILY_EXTRACTION_PLAN.md'
const docsReadmePath = 'docs/README.md'
const packageJsonPath = 'package.json'
const sourceCommonPath = 'packages/hxhx-core/src/backend/source/SourceTargetCommon.hx'
const facadePath = 'packages/hxhx-core/src/backend/source/SourceNativeBackend.hx'
const mvpCorePath = 'packages/hxhx-core/src/backend/source/SourceMvpTargetCore.hx'
const javaCorePath = 'packages/hxhx-core/src/backend/source/JavaSourceTargetCore.hx'
const phpCorePath = 'packages/hxhx-core/src/backend/source/PhpSourceTargetCore.hx'
const runtimeStrategyPath = 'docs/02-user-guide/SOURCE_NATIVE_RUNTIME_PACKAGING_STRATEGY.md'

function fail(message) {
  console.error(`[source-native-target-family-plan-check] ERROR: ${message}`)
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

function requireDirectory(dirPath) {
  if (!fs.existsSync(dirPath) || !fs.statSync(dirPath).isDirectory()) {
    fail(`missing required directory: ${dirPath}`)
  }
}

function main() {
  const plan = readText(planPath)
  const docsReadme = readText(docsReadmePath)
  const packageJson = readText(packageJsonPath)
  const sourceCommon = readText(sourceCommonPath)
  const facade = readText(facadePath)
  const mvpCore = readText(mvpCorePath)
  const javaCore = readText(javaCorePath)
  const phpCore = readText(phpCorePath)
  const runtimeStrategy = readText(runtimeStrategyPath)

  for (const snippet of [
    'SOURCE_NATIVE_TARGET_FAMILY_PLAN:PASS',
    'haxe_ocaml-cy8e',
    'SourceNativeBackend.hx',
    'JavaSourceTargetCore.hx',
    'PhpSourceTargetCore.hx',
    'SourceMvpTargetCore.hx',
    'SOURCE_NATIVE_RUNTIME_PACKAGING_STRATEGY.md',
    'SourceSharedLowering',
    'CsSourceTargetCore',
    'PythonSourceTargetCore',
    'LuaSourceTargetCore',
    'README/North Star progress bars recorded as unchanged',
  ]) {
    requireIncludes(planPath, plan, snippet)
  }

  for (const snippet of [
    'class SourceNativeBackend',
    'JavaSourceTargetCore.emit',
    'PhpSourceTargetCore.emit',
    'SourceMvpTargetCore.emit',
    'PYTHON_TARGET_ID',
    'JAVA_TARGET_ID',
    'CS_TARGET_ID',
    'PHP_TARGET_ID',
    'LUA_TARGET_ID',
  ]) {
    requireIncludes(facadePath, facade, snippet)
  }

  for (const snippet of [
    'enum SourceNativeTarget',
    'public static function emitTarget',
    'readSourceNativeTemplate',
    'appendSourceNativeTemplateLines',
    'renderExpr',
    'renderStmt',
    'phpSyntaxIntrinsicCall',
    'csLibIntrinsicCall',
    'renderPhpSupportClasses',
    'renderPythonSupportClasses',
    'renderLuaSupportPrelude',
    'renderJavaSupportClass',
    'renderCsSupportClass',
  ]) {
    requireIncludes(sourceCommonPath, sourceCommon, snippet)
  }

  requireIncludes(mvpCorePath, mvpCore, 'Python, C#, and Lua')
  requireIncludes(javaCorePath, javaCore, 'SourceTargetCommon.emitTarget(Java')
  requireIncludes(phpCorePath, phpCore, 'SourceTargetCommon.emitTarget(Php')
  requireIncludes(runtimeStrategyPath, runtimeStrategy, 'Source-Native Runtime Packaging Strategy')
  requireIncludes(runtimeStrategyPath, runtimeStrategy, 'Current Inventory')
  requireIncludes(runtimeStrategyPath, runtimeStrategy, 'Migration Plan')
  requireIncludes(runtimeStrategyPath, runtimeStrategy, 'README Goals status reviewed')
  requireIncludes(docsReadmePath, docsReadme, 'SOURCE_NATIVE_TARGET_FAMILY_EXTRACTION_PLAN.md')
  requireIncludes(packageJsonPath, packageJson, 'guard:source-native-target-family-plan')

  for (const dir of [
    'packages/hxhx-core/source-templates/cs',
    'packages/hxhx-core/source-templates/java',
    'packages/hxhx-core/source-templates/lua',
    'packages/hxhx-core/source-templates/php',
    'packages/hxhx-core/source-templates/python',
  ]) {
    requireDirectory(dir)
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Source-native target-family extraction plan is wired to current seams')
  console.log('SOURCE_NATIVE_TARGET_FAMILY_PLAN:PASS')
}

main()
