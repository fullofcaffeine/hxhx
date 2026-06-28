#!/usr/bin/env node
/**
 * Guard the Full1 release go/no-go decision contract.
 */

const fs = require('fs')

const docPath = 'docs/00-project/FULL1_RELEASE_GO_NO_GO.md'
const publicChecklistPath = 'docs/00-project/PUBLIC_1_0_CHECKLIST.md'
const fullContractPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const ciGatesPath = 'docs/00-project/CI_GATES.md'
const scopeManifestPath = 'docs/02-user-guide/compat/full-1.0-scope.json'
const rcWorkflowPath = '.github/workflows/gate-full1-rc.yml'
const rcEvaluatorPath = 'scripts/ci/full1-rc-gate.js'
const releaseMarker = 'FULL1_RELEASE_GO:PASS'

const requiredDocSnippets = [
  'Full1 Release Go/No-Go',
  'Scoped 1.0',
  'Full 1.0',
  scopeManifestPath,
  publicChecklistPath,
  rcWorkflowPath,
  rcEvaluatorPath,
  '.artifacts/full1/rc/full1-rc.summary.json',
  'full1-rc-summary.v1',
  'missingMarkers',
  'requiredMarkers',
  releaseMarker,
  'No-go decision',
  'haxe.ocaml-f1cl.7'
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

function main() {
  const doc = readUtf8(docPath)
  const checklist = readUtf8(publicChecklistPath)
  const fullContract = readUtf8(fullContractPath)
  const ciGates = readUtf8(ciGatesPath)
  const scope = readJson(scopeManifestPath)
  const rcWorkflow = readUtf8(rcWorkflowPath)
  const rcEvaluator = readUtf8(rcEvaluatorPath)

  for (const snippet of requiredDocSnippets) {
    requireIncludes(docPath, doc, snippet)
  }

  requireIncludes(publicChecklistPath, checklist, '## Scoped 1.0')
  requireIncludes(publicChecklistPath, checklist, '## Full 1.0')
  requireIncludes(publicChecklistPath, checklist, releaseMarker)
  requireIncludes(publicChecklistPath, checklist, docPath)

  requireIncludes(fullContractPath, fullContract, docPath)
  requireIncludes(ciGatesPath, ciGates, docPath)
  requireIncludes(ciGatesPath, ciGates, releaseMarker)

  if (scope) {
    const planned = scope.full && scope.full.requiredMarkersPlanned
    if (!Array.isArray(planned)) {
      fail(`${scopeManifestPath} must define full.requiredMarkersPlanned[]`)
    } else if (!planned.includes(releaseMarker)) {
      fail(`${scopeManifestPath} must include ${releaseMarker}`)
    }
  }

  requireIncludes(rcWorkflowPath, rcWorkflow, releaseMarker)
  requireIncludes(rcWorkflowPath, rcWorkflow, 'full1-rc.summary.json')
  requireIncludes(rcWorkflowPath, rcWorkflow, 'actions/upload-artifact@v4')
  requireIncludes(rcWorkflowPath, rcWorkflow, rcEvaluatorPath)

  requireIncludes(rcEvaluatorPath, rcEvaluator, scopeManifestPath)
  requireIncludes(rcEvaluatorPath, rcEvaluator, 'requiredMarkers')
  requireIncludes(rcEvaluatorPath, rcEvaluator, 'missingMarkers')
  requireIncludes(rcEvaluatorPath, rcEvaluator, releaseMarker)
  requireIncludes(rcEvaluatorPath, rcEvaluator, 'full1-rc-summary.v1')

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full1 release go/no-go contract is valid')
}

main()
