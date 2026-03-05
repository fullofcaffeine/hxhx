#!/usr/bin/env node
/**
 * full1-scope-contract-check.js
 *
 * Guardrail for Full-vs-Scoped 1.0 contract drift:
 * - required contract files must exist and parse,
 * - required scoped markers must map to existing workflow files,
 * - canonical docs must explicitly disambiguate Scoped 1.0 vs Full 1.0.
 */

const fs = require('fs')

const contractDocPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const scopeManifestPath = 'docs/02-user-guide/compat/full-1.0-scope.json'

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function readUtf8(path) {
  return fs.readFileSync(path, 'utf8')
}

function exists(path) {
  return fs.existsSync(path)
}

function isDisambiguatedLine(line) {
  if (/\b1\.0\.0\b/.test(line)) return true
  if (/\b1\.1\+/.test(line)) return true
  if (/\bfull-1\.0\b/i.test(line)) return true
  if (/\bscoped-1\.0\b/i.test(line)) return true
  if (/\bPost-Scoped-1\.0\b/.test(line)) return true
  if (/\bScoped 1\.0\b/i.test(line)) return true
  if (/\bFull 1\.0\b/i.test(line)) return true
  return false
}

function checkDocDisambiguation(path) {
  if (!exists(path)) {
    fail(`missing disambiguation doc: ${path}`)
    return
  }

  const lines = readUtf8(path).split(/\r?\n/)
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i]
    if (!/\b1\.0\b/.test(line)) continue
    if (isDisambiguatedLine(line)) continue
    fail(`${path}:${i + 1} has ambiguous 1.0 wording (use Scoped 1.0 or Full 1.0): ${line.trim()}`)
  }
}

function checkRequiredMarkerWorkflowMap(requiredMarkers) {
  for (const entry of requiredMarkers) {
    const marker = entry && entry.marker
    const workflow = entry && entry.workflow
    if (!marker || !workflow) {
      fail('scoped.requiredMarkers entries must contain both "marker" and "workflow"')
      continue
    }
    if (!exists(workflow)) {
      fail(`workflow listed in scope contract does not exist: ${workflow}`)
      continue
    }

    const workflowText = readUtf8(workflow)
    const markerPrefix = marker.split(':')[0]
    if (!workflowText.includes(marker) && !workflowText.includes(markerPrefix)) {
      fail(`workflow ${workflow} does not reference required marker "${marker}"`)
    }
  }
}

function main() {
  if (!exists(contractDocPath)) {
    fail(`missing contract doc: ${contractDocPath}`)
    return
  }
  if (!exists(scopeManifestPath)) {
    fail(`missing scope manifest: ${scopeManifestPath}`)
    return
  }

  const contractDoc = readUtf8(contractDocPath)
  if (!contractDoc.includes(scopeManifestPath)) {
    fail(`contract doc must reference scope manifest path: ${scopeManifestPath}`)
  }
  if (!/\bScoped 1\.0\b/.test(contractDoc) || !/\bFull 1\.0\b/.test(contractDoc)) {
    fail('contract doc must explicitly contain both "Scoped 1.0" and "Full 1.0"')
  }

  let scope = null
  try {
    scope = JSON.parse(readUtf8(scopeManifestPath))
  } catch (error) {
    fail(`invalid JSON in ${scopeManifestPath}: ${error.message}`)
    return
  }

  if (!scope || typeof scope !== 'object') {
    fail('scope manifest must be a JSON object')
    return
  }
  if (scope.haxeCompatibilityBaseline !== '4.3.7') {
    fail(`scope baseline must be 4.3.7 (received: ${scope.haxeCompatibilityBaseline})`)
  }
  if (!scope.scoped || !Array.isArray(scope.scoped.requiredMarkers)) {
    fail('scope manifest must define scoped.requiredMarkers[]')
  } else {
    checkRequiredMarkerWorkflowMap(scope.scoped.requiredMarkers)
  }
  if (!Array.isArray(scope.docsMustDisambiguate) || scope.docsMustDisambiguate.length === 0) {
    fail('scope manifest must define docsMustDisambiguate[]')
  } else {
    for (const path of scope.docsMustDisambiguate) {
      checkDocDisambiguation(path)
    }
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full-vs-scoped 1.0 contract is valid')
  console.log('FULL1_SCOPE_CONTRACT:PASS')
}

main()
