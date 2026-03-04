#!/usr/bin/env node
/**
 * bootstrap-plugin-kind-parity-check.js
 *
 * Guardrail for bootstrap snapshot parity:
 * - source of truth is BackendPluginManifestKind (Haxe source);
 * - bootstrap parser/resolver must accept exactly the same backend kinds.
 *
 * Why
 * - A stale bootstrap snapshot can silently diverge from source behavior.
 * - This check keeps source-built and bootstrap-built kind handling aligned.
 */

const fs = require('fs')

const sourceKindFile = 'packages/hxhx-core/src/backend/plugin/BackendPluginManifestKind.hx'
const bootstrapParserFile = 'packages/hxhx/bootstrap_out/backend_plugin_BackendPluginManifestParser.ml'
const bootstrapResolverFile = 'packages/hxhx/bootstrap_out/hxhx_BackendPluginManifestResolver.ml'
const legacyKind = 'haxe-provider'

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function readUtf8(path) {
  return fs.readFileSync(path, 'utf8')
}

function sortedUnique(values) {
  return Array.from(new Set(values)).sort()
}

function extractSourceKinds(source) {
  const out = []
  const re = /var\s+\w+\s*=\s*"([^"]+)";/g
  let match = re.exec(source)
  while (match !== null) {
    out.push(match[1])
    match = re.exec(source)
  }
  return sortedUnique(out)
}

function between(text, startMarker, endMarker) {
  const start = text.indexOf(startMarker)
  if (start < 0) return null
  const end = text.indexOf(endMarker, start + startMarker.length)
  if (end < 0) return null
  return text.slice(start, end)
}

function extractBootstrapKindsFromMatchBlock(text) {
  const out = []
  const re = /\|\s+"([^"]+)"\s*->/g
  let match = re.exec(text)
  while (match !== null) {
    out.push(match[1])
    match = re.exec(text)
  }
  return sortedUnique(out)
}

function sameArray(a, b) {
  if (a.length !== b.length) return false
  for (let i = 0; i < a.length; i += 1) {
    if (a[i] !== b[i]) return false
  }
  return true
}

function assertKindParity(label, actualKinds, expectedKinds) {
  if (sameArray(actualKinds, expectedKinds)) return
  fail(
    `${label} backend kind set mismatch.\n` +
    `  expected: [${expectedKinds.join(', ')}]\n` +
    `  actual:   [${actualKinds.join(', ')}]`
  )
}

function assertNoLegacyKind(path, content) {
  if (content.indexOf(legacyKind) >= 0) {
    fail(`legacy backend kind "${legacyKind}" found in ${path}`)
  }
}

function main() {
  let sourceText = ''
  let parserText = ''
  let resolverText = ''

  try {
    sourceText = readUtf8(sourceKindFile)
    parserText = readUtf8(bootstrapParserFile)
    resolverText = readUtf8(bootstrapResolverFile)
  } catch (error) {
    fail(`failed to read required files: ${error.message}`)
    return
  }

  const sourceKinds = extractSourceKinds(sourceText)
  if (sourceKinds.length === 0) {
    fail(`no backend kinds found in ${sourceKindFile}`)
    return
  }

  const parserBlock = between(parserText, 'let parseKind = fun', 'let validate = fun')
  if (parserBlock == null) {
    fail(`unable to locate parseKind block in ${bootstrapParserFile}`)
    return
  }
  const parserKinds = extractBootstrapKindsFromMatchBlock(parserBlock)

  const resolverBlock = between(
    resolverText,
    'let providerTypeNamesForManifest = fun',
    'let providerTypeNamesForManifestPath = fun'
  )
  if (resolverBlock == null) {
    fail(`unable to locate providerTypeNamesForManifest block in ${bootstrapResolverFile}`)
    return
  }
  const resolverKinds = extractBootstrapKindsFromMatchBlock(resolverBlock)

  assertKindParity(bootstrapParserFile, parserKinds, sourceKinds)
  assertKindParity(bootstrapResolverFile, resolverKinds, sourceKinds)
  assertNoLegacyKind(bootstrapParserFile, parserText)
  assertNoLegacyKind(bootstrapResolverFile, resolverText)

  if (!process.exitCode) {
    console.log(`[ci:guards] OK: bootstrap backend kind parity (${sourceKinds.join(', ')})`)
  }
}

main()
