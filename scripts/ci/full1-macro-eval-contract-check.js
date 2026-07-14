#!/usr/bin/env node
/**
 * Guard the Full 1.0 macro/eval parity contract.
 *
 * This is a documentation-contract check only. It proves that the release criteria,
 * marker set, blocker map, and non-goals are explicit; it does not run macro/eval
 * parity workloads.
 */

const fs = require('fs')

const docPath = 'docs/00-project/MACRO_EVAL_PARITY_CONTRACT.md'
const macroBlockersPath = 'docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md'
const parityMapPath = 'docs/00-project/PARITY_MAP_HAXE_4_3_7.md'
const fullContractPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const fullScopePath = 'docs/02-user-guide/compat/full-1.0-scope.json'

const requiredDocSnippets = [
  'FULL1_MACRO_EVAL_CONTRACT:PASS',
  'MACRO_RUNTIME_PARITY_WEEKLY:PASS',
  'FULL1_MACRO_PARITY:PASS',
  'MACRO_RUNTIME_EXTERNAL_HOST_ARTIFACT:PASS',
  'FULL1_EVAL_NATIVE:PASS',
  'FULL1_MACRO_EVAL_PARITY:PASS',
  '## Blocker Map',
  '## Non-Goals',
  'haxe.ocaml-f1cl.4.2',
  'haxe.ocaml-f1cl.4.3',
  'haxe_ocaml-vhk47.1',
  'haxe_ocaml-vhk47.3',
  'Raw source-host Reflaxe custom-target discovery',
  'Treating `--compat` or stage0 delegation as native Full 1.0 macro/eval evidence',
]

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function readUtf8(path) {
  if (!fs.existsSync(path)) {
    fail(`missing required file: ${path}`)
    return ''
  }
  return fs.readFileSync(path, 'utf8')
}

function requireIncludes(path, text, snippet) {
  if (!text.includes(snippet)) fail(`${path} must include: ${snippet}`)
}

function main() {
  const doc = readUtf8(docPath)
  const macroBlockers = readUtf8(macroBlockersPath)
  const parityMap = readUtf8(parityMapPath)
  const fullContract = readUtf8(fullContractPath)
  const fullScope = readUtf8(fullScopePath)

  for (const snippet of requiredDocSnippets) {
    requireIncludes(docPath, doc, snippet)
  }

  requireIncludes(macroBlockersPath, macroBlockers, 'MRP-B5')
  requireIncludes(macroBlockersPath, macroBlockers, 'haxe_ocaml-vhk47.1')
  requireIncludes(macroBlockersPath, macroBlockers, 'MRP-B6')
  requireIncludes(macroBlockersPath, macroBlockers, 'haxe_ocaml-vhk47.3')
  requireIncludes(macroBlockersPath, macroBlockers, 'MACRO_HOST_LIFECYCLE_DECISION.md')
  requireIncludes(parityMapPath, parityMap, 'FULL1_EVAL_NATIVE:PASS')
  requireIncludes(parityMapPath, parityMap, 'FULL1_MACRO_EVAL_PARITY:PASS')
  requireIncludes(fullContractPath, fullContract, docPath)
  requireIncludes(fullScopePath, fullScope, 'FULL1_MACRO_EVAL_PARITY:PASS')

  if (/\bTBD\b|\bTODO\b|<placeholder>/i.test(doc)) {
    fail(`${docPath} must not contain placeholder closure language`)
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full1 macro/eval parity contract is valid')
  console.log('FULL1_MACRO_EVAL_CONTRACT:PASS')
}

main()
