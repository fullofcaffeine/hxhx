#!/usr/bin/env node
/**
 * Guard the Full1 flake policy and quarantine allowlist.
 */

const fs = require('fs')

const docPath = 'docs/00-project/FULL1_FLAKE_POLICY.md'
const allowlistPath = 'docs/00-project/FULL1_FLAKE_ALLOWLIST.json'
const fullContractPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const scopeManifestPath = 'docs/02-user-guide/compat/full-1.0-scope.json'
const parityMapPath = 'docs/00-project/PARITY_MAP_FULL_1_0.json'
const ciGatesPath = 'docs/00-project/CI_GATES.md'
const rcWorkflowPath = '.github/workflows/gate-full1-rc.yml'
const marker = 'FULL1_FLAKE_POLICY:PASS'

const requiredDocSnippets = [
  marker,
  'Full1 gates must never silently skip required evidence',
  'FULL1_FLAKE_ALLOWLIST.json',
  'owner',
  'justification',
  'expiresAt',
  'retryLimit',
  'Expired quarantine entries block',
  'scripts/ci/full1-flake-policy-check.js'
]

const requiredEntryFields = [
  'id',
  'owner',
  'bead',
  'workflow',
  'marker',
  'justification',
  'retryLimit',
  'expiresAt'
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

function readJson(path) {
  const text = readUtf8(path)
  if (!text) return null
  try {
    return JSON.parse(text)
  } catch (error) {
    fail(`invalid JSON in ${path}: ${error.message}`)
    return null
  }
}

function requireIncludes(path, text, snippet) {
  if (!text.includes(snippet)) fail(`${path} must include: ${snippet}`)
}

function validateQuarantine(entry, index) {
  const label = `${allowlistPath} quarantines[${index}]`
  for (const field of requiredEntryFields) {
    if (entry[field] === undefined || entry[field] === null || entry[field] === '') {
      fail(`${label} must define non-empty ${field}`)
    }
  }
  if (!Number.isInteger(entry.retryLimit) || entry.retryLimit < 0 || entry.retryLimit > 2) {
    fail(`${label}.retryLimit must be an integer from 0 to 2`)
  }
  const expiresAt = Date.parse(`${entry.expiresAt}T00:00:00Z`)
  if (Number.isNaN(expiresAt)) {
    fail(`${label}.expiresAt must be an ISO date (YYYY-MM-DD)`)
    return
  }
  if (expiresAt <= Date.now()) {
    fail(`${label}.expiresAt is expired: ${entry.expiresAt}`)
  }
  if (!/^haxe\.ocaml-|^haxe_ocaml-/.test(String(entry.bead))) {
    fail(`${label}.bead must reference a haxe.ocaml bead`)
  }
  if (!String(entry.marker).endsWith(':PASS')) {
    fail(`${label}.marker must be a PASS marker`)
  }
  if (String(entry.justification).trim().length < 20) {
    fail(`${label}.justification must be specific enough for release review`)
  }
}

function main() {
  const doc = readUtf8(docPath)
  const allowlist = readJson(allowlistPath)
  const fullContract = readUtf8(fullContractPath)
  const scopeManifest = readUtf8(scopeManifestPath)
  const parityMap = readUtf8(parityMapPath)
  const ciGates = readUtf8(ciGatesPath)
  const rcWorkflow = readUtf8(rcWorkflowPath)

  for (const snippet of requiredDocSnippets) {
    requireIncludes(docPath, doc, snippet)
  }
  requireIncludes(fullContractPath, fullContract, docPath)
  requireIncludes(scopeManifestPath, scopeManifest, marker)
  requireIncludes(parityMapPath, parityMap, marker)
  requireIncludes(ciGatesPath, ciGates, marker)
  requireIncludes(rcWorkflowPath, rcWorkflow, marker)
  requireIncludes(rcWorkflowPath, rcWorkflow, 'scripts/ci/full1-flake-policy-check.js')

  if (!allowlist) return
  if (allowlist.schema !== 'full1-flake-allowlist.v1') {
    fail(`${allowlistPath} schema must be full1-flake-allowlist.v1`)
  }
  if (allowlist.policy !== docPath) {
    fail(`${allowlistPath} policy must be ${docPath}`)
  }
  if (!Array.isArray(allowlist.quarantines)) {
    fail(`${allowlistPath} must define quarantines[]`)
  } else {
    allowlist.quarantines.forEach(validateQuarantine)
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full1 flake policy is valid')
  console.log(marker)
}

main()
