#!/usr/bin/env node
/**
 * reflaxe-hxhx-core-boundary-check.js
 *
 * Guardrail for the accepted Reflaxe / hxhx architecture boundary:
 * - hxhx parser/resolver/typer/core diagnostic ownership stays ordinary Haxe;
 * - Reflaxe-style APIs belong at native artifact, backend, plugin, and target
 *   promotion seams;
 * - deeper Reflaxe coupling needs an explicit architecture bead.
 */

const fs = require('fs')
const cp = require('child_process')
const path = require('path')

const hxhxCoreRoot = 'packages/hxhx-core/src/'
const hxhxStage3CoreFiles = new Set([
  'packages/hxhx/src/hxhx/Stage3Compiler.hx',
  'packages/hxhx/src/hxhx/Stage3DiagnosticsSupport.hx',
])

const coreRootPrefixes = [
  'CSharpNoEmitDiagnostics',
  'Hx',
  'JavaNoEmitDiagnostics',
  'LazyTypeLoader',
  'ModuleLoader',
  'ParsedModule',
  'ParserStage',
  'ResolvedModule',
  'ResolverStage',
  'Ty',
]

const forbiddenPatterns = [
  {
    label: 'reflaxe_import',
    re: /^\s*(?:import|using)\s+reflaxe(?:\.|;)/,
  },
  {
    label: 'backend_reflaxe_import',
    re: /^\s*(?:import|using)\s+backend\.reflaxe(?:\.|;)/,
  },
  {
    label: 'qualified_reflaxe_reference',
    re: /\b(?:reflaxe|backend\.reflaxe)\./,
  },
]

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function gitTrackedAll() {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function isCommentLine(line) {
  const trimmed = line.trim()
  return (
    trimmed.startsWith('//') ||
    trimmed.startsWith('/*') ||
    trimmed.startsWith('*') ||
    trimmed.startsWith('*/')
  )
}

function isCoreOwnershipFile(filePath) {
  if (!filePath.endsWith('.hx')) return false
  if (hxhxStage3CoreFiles.has(filePath)) return true
  if (!filePath.startsWith(hxhxCoreRoot)) return false
  if (filePath.startsWith(`${hxhxCoreRoot}backend/`)) return false
  if (filePath.startsWith(`${hxhxCoreRoot}native/`)) return false

  const base = path.basename(filePath, '.hx')
  return coreRootPrefixes.some(prefix => base.startsWith(prefix))
}

function main() {
  const violations = []

  for (const filePath of gitTrackedAll()) {
    if (!isCoreOwnershipFile(filePath)) continue

    let text = ''
    try {
      text = fs.readFileSync(filePath, 'utf8')
    } catch (_) {
      continue
    }

    const lines = text.split('\n')
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index]
      if (isCommentLine(line)) continue
      for (const pattern of forbiddenPatterns) {
        if (pattern.re.test(line)) {
          violations.push(`${filePath}:${index + 1} [${pattern.label}] ${line.trim()}`)
          break
        }
      }
    }
  }

  if (violations.length > 0) {
    fail(
      'Reflaxe framework APIs must not enter hxhx parser/resolver/typer/core diagnostic ownership files. ' +
      'Keep them at backend/plugin/native-artifact seams or add an explicit architecture bead.\n- ' +
      violations.slice(0, 80).join('\n- ')
    )
    return
  }

  console.log('[ci:guards] OK: Reflaxe framework boundary stays out of hxhx compiler core')
}

main()
