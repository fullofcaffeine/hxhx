#!/usr/bin/env node
'use strict'

/**
 * Builds the Full1 plugin aggregate from three same-run proof artifacts.
 *
 * A matrix job result can stop the gate, but it cannot create a pass marker.
 * This evaluator opens each proof receipt, checks its declared route and
 * runtime result, and re-hashes the uploaded plugin file before aggregating.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const AGGREGATE_SCHEMA = 'full1-plugin-parity-summary.v3'
const PROOF_SCHEMA = 'full1-plugin-proof.v1'
const AGGREGATE_MARKER = 'FULL1_PLUGIN_PARITY:PASS'
const PINNED_REFLAXE_ELIXIR = '5b322236e0627f8322394e819cf28ba6c1271a83'

const PROOFS = [
  {
    id: 'upstream-to-hxhx',
    artifactPrefix: 'full1-plugin-upstream-to-hxhx',
    summaryName: 'full1-plugin-upstream-to-hxhx.summary.json',
    marker: 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS',
    validate: validateUpstreamToHxhx,
  },
  {
    id: 'hxhx-to-hxhx',
    artifactPrefix: 'full1-plugin-hxhx-to-hxhx',
    summaryName: 'full1-plugin-hxhx-to-hxhx.summary.json',
    marker: 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS',
    validate: validateHxhxToHxhx,
  },
  {
    id: 'upstream-host-adapter',
    artifactPrefix: 'full1-plugin-upstream-host-adapter',
    summaryName: 'full1-plugin-upstream-host-adapter.summary.json',
    marker: 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS',
    validate: validateUpstreamHostAdapter,
  },
]

function parseArgs(argv) {
  const args = {}
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index]
    if (!flag.startsWith('--')) throw new Error(`unexpected argument: ${flag}`)
    const name = flag.slice(2)
    const value = argv[index + 1]
    if (!value || value.startsWith('--')) throw new Error(`missing value for ${flag}`)
    args[name] = value
    index += 1
  }
  for (const name of ['artifacts-dir', 'output', 'candidate-sha', 'run-id', 'run-attempt', 'matrix-result']) {
    if (!args[name]) throw new Error(`missing --${name}`)
  }
  return {
    artifactsDir: path.resolve(args['artifacts-dir']),
    output: path.resolve(args.output),
    candidateSha: args['candidate-sha'],
    runId: String(args['run-id']),
    runAttempt: String(args['run-attempt']),
    matrixResult: args['matrix-result'],
  }
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function isSha256(value) {
  return typeof value === 'string' && /^[0-9a-f]{64}$/i.test(value)
}

function findFiles(directory, fileName) {
  const matches = []
  if (!fs.existsSync(directory)) return matches
  const visit = current => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const resolved = path.join(current, entry.name)
      if (entry.isDirectory()) visit(resolved)
      else if (entry.name === fileName) matches.push(resolved)
    }
  }
  visit(directory)
  return matches
}

function requireValue(condition, message) {
  if (!condition) throw new Error(message)
}

function verifyEvidenceArtifact(summaryPath, relativeFile, expectedDigest) {
  requireValue(typeof relativeFile === 'string' && relativeFile.length > 0,
    'plugin evidence artifact path is missing')
  requireValue(!path.isAbsolute(relativeFile), 'plugin evidence artifact path must be relative')
  const summaryDirectory = path.dirname(summaryPath)
  const artifactPath = path.resolve(summaryDirectory, relativeFile)
  const relativeResolved = path.relative(summaryDirectory, artifactPath)
  requireValue(relativeResolved !== '..'
    && !relativeResolved.startsWith(`..${path.sep}`)
    && !path.isAbsolute(relativeResolved),
    'plugin evidence artifact must stay beside its proof summary')
  requireValue(fs.existsSync(artifactPath) && fs.statSync(artifactPath).isFile(),
    `missing plugin evidence artifact ${relativeFile}`)
  requireValue(isSha256(expectedDigest), 'plugin artifact SHA-256 is missing or invalid')
  const actualDigest = sha256File(artifactPath)
  requireValue(actualDigest === expectedDigest, 'plugin artifact digest does not match the uploaded file')
  return actualDigest
}

function validateCommon(summary, spec, context) {
  requireValue(summary && typeof summary === 'object', 'summary is not an object')
  requireValue(summary.schema === PROOF_SCHEMA, `expected schema ${PROOF_SCHEMA}`)
  requireValue(summary.synthetic === false, 'proof must be authentic, not synthetic')
  requireValue(summary.route === spec.id, `expected route ${spec.id}`)
  requireValue(summary.candidateSha === context.candidateSha, 'candidate SHA mismatch')
  requireValue(String(summary.workflowRun?.id) === context.runId, 'workflow run ID mismatch')
  requireValue(String(summary.workflowRun?.attempt) === context.runAttempt, 'workflow run attempt mismatch')
  requireValue(summary.marker === spec.marker, `expected marker ${spec.marker}`)
  requireValue(summary.result === spec.marker, `expected result ${spec.marker}`)
}

function validatePlugin(summary, pluginId) {
  requireValue(summary.plugin?.pluginId === pluginId, `expected plugin ID ${pluginId}`)
  requireValue(summary.plugin?.targetId === 'js-native', 'expected js-native target')
  requireValue(summary.plugin?.artifactKind === 'ocaml-dynlink', 'expected OCaml dynlink artifact')
  requireValue(summary.sampleCompile?.providerType === 'backend.js.JsBackend', 'unexpected selected provider type')
  requireValue(summary.sampleCompile?.selectedImpl === 'provider/js-native-wrapper', 'unexpected selected backend implementation')
  requireValue(summary.sampleCompile?.runtimeStdout === 'sum=6', 'generated program output did not pass')
}

function validateUpstreamToHxhx(summary) {
  requireValue(summary.hostCompiler?.kind === 'upstream-haxe', 'upstream route used the wrong build compiler')
  requireValue(summary.hostCompiler?.version === '4.3.7', 'upstream route did not use Haxe 4.3.7')
  requireValue(summary.hxhx?.stage0Forbidden === true, 'upstream route did not forbid stage0 in hxhx')
  validatePlugin(summary, 'full1.reflaxe.ocaml.upstream')
  requireValue(summary.plugin.loadSideEffect === 'full1_upstream_plugin_loaded=ok', 'upstream route did not prove plugin load')
}

function validateHxhxToHxhx(summary) {
  requireValue(summary.pluginCompiler?.kind === 'hxhx-stage3', 'native route used the wrong plugin compiler')
  requireValue(summary.pluginCompiler?.stage0Forbidden === true, 'native plugin build did not forbid stage0')
  requireValue(summary.hxhx?.stage0Forbidden === true, 'native plugin load did not forbid stage0')
  requireValue(summary.sourceBuildCompiler?.kind === 'stage0-haxe-for-hxhx-binary-build', 'native compiler bootstrap origin is missing')
  requireValue(summary.sourceBuildCompiler?.version === '4.3.7', 'native compiler bootstrap did not use Haxe 4.3.7')
  validatePlugin(summary, 'full1.reflaxe.ocaml.hxhx')
  requireValue(summary.plugin.loadSideEffect === 'full1_hxhx_plugin_loaded=ok', 'native route did not prove plugin load')
}

function validateUpstreamHostAdapter(summary) {
  requireValue(summary.artifactCompiler?.kind === 'upstream-haxe', 'host-adapter route used the wrong artifact compiler')
  requireValue(summary.artifactCompiler?.version === '4.3.7', 'host-adapter route did not use Haxe 4.3.7')
  requireValue(summary.upstreamHostAdapter?.kind === 'haxe-eval', 'unexpected upstream host adapter')
  requireValue(summary.upstreamHostAdapter?.loadApi === 'eval.vm.Context.loadPlugin', 'unexpected upstream load API')
  requireValue(summary.upstreamHostAdapter?.crossHostBinaryCompatibility === false, 'host-adapter proof overclaims cross-host compatibility')
  requireValue(summary.upstreamHostAdapter?.trueCompilerTargetPluginAbi === false, 'host-adapter proof overclaims an upstream native ABI')
  requireValue(summary.source?.commit === PINNED_REFLAXE_ELIXIR, 'unexpected Reflaxe.Elixir workload revision')
  requireValue(summary.pluginArtifact?.loadStatus === 'pass', 'upstream host adapter did not load the plugin')
  requireValue(Array.isArray(summary.pluginArtifact?.builtArtifacts) && summary.pluginArtifact.builtArtifacts.length === 2,
    'host-adapter proof did not record both plugin artifacts')
  requireValue(summary.evidence?.upstreamProofResult === 'RPMX_HAXE_PLUGIN:PASS', 'upstream workload proof did not pass')
}

function artifactName(spec, context) {
  return `${spec.artifactPrefix}-${context.runId}-${context.runAttempt}`
}

/**
 * Validates the exact proof artifacts used by the plugin aggregate.
 *
 * The matrix job result remains a fail-safe control signal, but it cannot
 * create release markers. Each marker is recovered from a same-run proof
 * summary whose host, stage0, load, digest, and runtime claims are checked.
 */
function evaluate(context) {
  const errors = []
  const proofs = []
  if (!/^[0-9a-f]{40}$/i.test(context.candidateSha)) errors.push('candidate SHA must contain 40 hexadecimal characters')
  if (context.matrixResult !== 'success') errors.push(`plugin matrix result is ${context.matrixResult}`)

  for (const spec of PROOFS) {
    const name = artifactName(spec, context)
    const directory = path.join(context.artifactsDir, name)
    try {
      requireValue(fs.existsSync(directory) && fs.statSync(directory).isDirectory(), `missing artifact directory ${name}`)
      const summaries = findFiles(directory, spec.summaryName)
      requireValue(summaries.length === 1, `${name} must contain exactly one ${spec.summaryName}; found ${summaries.length}`)
      const summaryPath = summaries[0]
      const summary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'))
      validateCommon(summary, spec, context)
      spec.validate(summary)
      const plugin = spec.id === 'upstream-host-adapter' ? summary.pluginArtifact : summary.plugin
      const pluginDigest = verifyEvidenceArtifact(summaryPath, plugin.evidenceArtifact, plugin.artifactSha256)
      proofs.push({
        id: spec.id,
        artifact_name: name,
        summary_path: path.relative(directory, summaryPath),
        summary_sha256: sha256File(summaryPath),
        summary_schema: summary.schema,
        plugin_artifact_sha256: pluginDigest,
        marker: spec.marker,
        verified: true,
      })
    } catch (error) {
      errors.push(`${name}: ${error.message}`)
    }
  }

  const passed = errors.length === 0 && proofs.length === PROOFS.length
  return {
    schema: AGGREGATE_SCHEMA,
    synthetic: false,
    workflow: 'Full1 / Plugin Parity',
    candidate_sha: context.candidateSha,
    run_id: context.runId,
    run_attempt: context.runAttempt,
    jobs: {
      full1_plugin_proofs: { result: context.matrixResult },
    },
    required_markers: PROOFS.map(spec => spec.marker),
    proofs,
    errors,
    expected_markers: [AGGREGATE_MARKER],
    emitted_markers: passed ? [AGGREGATE_MARKER] : [],
  }
}

function main() {
  let context
  try {
    context = parseArgs(process.argv.slice(2))
    const summary = evaluate(context)
    fs.mkdirSync(path.dirname(context.output), { recursive: true })
    fs.writeFileSync(context.output, JSON.stringify(summary, null, 2) + '\n')
    if (summary.errors.length > 0) {
      for (const error of summary.errors) console.error(`full1 plugin evidence: ${error}`)
      process.exit(1)
    }
    console.log(AGGREGATE_MARKER)
  } catch (error) {
    console.error(`full1 plugin evidence: ${error.message}`)
    process.exit(1)
  }
}

if (require.main === module) main()

module.exports = {
  AGGREGATE_MARKER,
  AGGREGATE_SCHEMA,
  PINNED_REFLAXE_ELIXIR,
  PROOF_SCHEMA,
  PROOFS,
  artifactName,
  evaluate,
  verifyEvidenceArtifact,
}
