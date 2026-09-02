#!/usr/bin/env node
/**
 * Guard the Full 1.0 plugin parity contract.
 *
 * This is a contract-shape check, not runtime proof. It proves that the
 * documented matrix and marker names remain connected to the artifact-backed
 * workflow and its fail-closed evaluator.
 */

const fs = require('fs')

const docPath = 'docs/00-project/PLUGIN_PARITY_FULL_1_0.md'
const parityMapPath = 'docs/00-project/PARITY_MAP_HAXE_4_3_7.md'
const fullParityMapPath = 'docs/00-project/PARITY_MAP_FULL_1_0.json'
const fullContractPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const scopeManifestPath = 'docs/02-user-guide/compat/full-1.0-scope.json'
const pluginWorkflowPath = '.github/workflows/full1-plugin-parity.yml'
const pluginEvidencePath = 'scripts/ci/full1-plugin-parity-evidence.js'
const full1WorkflowPath = '.github/workflows/gate-full1.yml'

const requiredDocSnippets = [
  'FULL1_PLUGIN_PARITY_CONTRACT:PASS',
  'FULL1_PLUGIN_PARITY:PASS',
  'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS',
  'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS',
  'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS',
  '## Host/Compiler Matrix',
  'upstream Haxe to hxhx',
  'hxhx strict to hxhx',
  'explicit upstream Haxe host-adapter proof',
  'eval.vm.Context.loadPlugin',
  'HXHX_FORBID_STAGE0=1',
  '`--compat` and other stage0 delegation paths do not count',
  'haxe.ocaml-f1cl.8.2',
  'haxe.ocaml-f1cl.8.3',
  'haxe.ocaml-f1cl.8.4',
  'haxe.ocaml-f1cl.8.5',
  'npm run test:full1:plugin:upstream-to-hxhx',
  'npm run test:full1:plugin:hxhx-to-hxhx',
  'npm run test:full1:plugin:upstream-host-adapter',
  'npm run test:full1:plugin:evidence',
  'full1-plugin-parity-summary.v3',
  "uploaded plugin file's SHA-256 checksum matches its receipt",
  '.github/workflows/full1-plugin-parity.yml',
  'FULL1_PLUGIN_PARITY:PASS` only after all three proof rows pass',
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
  const pluginWorkflow = readUtf8(pluginWorkflowPath)
  const pluginEvidence = readUtf8(pluginEvidencePath)
  const full1Workflow = readUtf8(full1WorkflowPath)

  for (const snippet of requiredDocSnippets) {
    requireIncludes(docPath, doc, snippet)
  }

  requireIncludes(parityMapPath, parityMap, 'FULL1_PLUGIN_PARITY_CONTRACT:PASS')
  requireIncludes(parityMapPath, parityMap, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS')
  requireIncludes(parityMapPath, parityMap, 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS')
  requireIncludes(parityMapPath, parityMap, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS')
  requireIncludes(parityMapPath, parityMap, 'FULL1_PLUGIN_PARITY:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'FULL1_PLUGIN_PARITY_CONTRACT:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS')
  requireIncludes(fullParityMapPath, fullParityMap, 'FULL1_PLUGIN_PARITY:PASS')
  requireIncludes(fullContractPath, fullContract, docPath)
  requireIncludes(scopeManifestPath, scopeManifest, 'FULL1_PLUGIN_PARITY_CONTRACT:PASS')
  requireIncludes(scopeManifestPath, scopeManifest, 'FULL1_PLUGIN_PARITY:PASS')
  requireIncludes(pluginWorkflowPath, pluginWorkflow, 'FULL1_PLUGIN_PARITY:PASS')
  requireIncludes(pluginWorkflowPath, pluginWorkflow, 'actions/download-artifact@v7')
  requireIncludes(pluginWorkflowPath, pluginWorkflow, 'actions/upload-artifact@v6')
  requireIncludes(pluginWorkflowPath, pluginWorkflow, 'scripts/ci/full1-plugin-parity-evidence.js')
  requireIncludes(pluginWorkflowPath, pluginWorkflow, 'full1_plugin_artifact_verification')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'full1-plugin-parity-summary.v3')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'full1-plugin-proof.v1')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'candidate SHA mismatch')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'plugin artifact digest does not match the uploaded file')
  requireIncludes(pluginEvidencePath, pluginEvidence, 'proof must be authentic, not synthetic')
  requireIncludes(full1WorkflowPath, full1Workflow, './.github/workflows/full1-plugin-parity.yml')
  requireIncludes(full1WorkflowPath, full1Workflow, 'FULL1_PLUGIN_PARITY:PASS')

  if (/\bTBD\b|\bTODO\b|<placeholder>/i.test(doc)) {
    fail(`${docPath} must not contain placeholder closure language`)
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full1 plugin parity contract is valid')
  console.log('FULL1_PLUGIN_PARITY_CONTRACT:PASS')
}

main()
