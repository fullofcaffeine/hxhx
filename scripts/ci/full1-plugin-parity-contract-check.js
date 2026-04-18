#!/usr/bin/env node
/**
 * Guard the Full 1.0 plugin parity contract.
 *
 * This is a documentation-contract check only. It proves that the release
 * matrix, marker names, non-goals, and follow-up proof owners are explicit.
 */

const fs = require('fs')

const docPath = 'docs/00-project/PLUGIN_PARITY_FULL_1_0.md'
const parityMapPath = 'docs/00-project/PARITY_MAP_HAXE_4_3_7.md'
const fullParityMapPath = 'docs/00-project/PARITY_MAP_FULL_1_0.json'
const fullContractPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const scopeManifestPath = 'docs/02-user-guide/compat/full-1.0-scope.json'

const requiredDocSnippets = [
  'FULL1_PLUGIN_PARITY_CONTRACT:PASS',
  'FULL1_PLUGIN_PARITY:PASS',
  'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS',
  '## Host/Compiler Matrix',
  'upstream Haxe to hxhx',
  'hxhx strict to hxhx',
  'explicit upstream Haxe host-adapter proof',
  'HXHX_FORBID_STAGE0=1',
  '`--compat` and other stage0 delegation paths do not count',
  'haxe.ocaml-f1cl.8.2',
  'haxe.ocaml-f1cl.8.3',
  'haxe.ocaml-f1cl.8.4',
  'haxe.ocaml-f1cl.8.5',
  'npm run test:full1:plugin:upstream-to-hxhx',
  'reflaxe.elixir` is example-only and non-blocking',
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
  const parityMap = readUtf8(parityMapPath)
  const fullParityMap = readUtf8(fullParityMapPath)
  const fullContract = readUtf8(fullContractPath)
  const scopeManifest = readUtf8(scopeManifestPath)

  for (const snippet of requiredDocSnippets) {
    requireIncludes(docPath, doc, snippet)
  }

  requireIncludes(parityMapPath, parityMap, 'FULL1_PLUGIN_PARITY_CONTRACT:PASS')
  requireIncludes(parityMapPath, parityMap, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS')
  requireIncludes(parityMapPath, parityMap, 'FULL1_PLUGIN_PARITY:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'FULL1_PLUGIN_PARITY_CONTRACT:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'FULL1_PLUGIN_PARITY:PASS')
  requireIncludes(fullContractPath, fullContract, docPath)
  requireIncludes(scopeManifestPath, scopeManifest, 'FULL1_PLUGIN_PARITY_CONTRACT:PASS')
  requireIncludes(scopeManifestPath, scopeManifest, 'FULL1_PLUGIN_PARITY:PASS')

  if (/\bTBD\b|\bTODO\b|<placeholder>/i.test(doc)) {
    fail(`${docPath} must not contain placeholder closure language`)
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full1 plugin parity contract is valid')
  console.log('FULL1_PLUGIN_PARITY_CONTRACT:PASS')
}

main()
