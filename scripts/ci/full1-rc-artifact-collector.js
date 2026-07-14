#!/usr/bin/env node
/**
 * Download and validate the exact child artifacts for one Full1 RC run.
 *
 * Artifact ZIP digests are checked against GitHub's API metadata before any
 * contained summary is allowed to contribute a marker.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')
const { rolePolicy, sha256File } = require('./full1-rc-gate')

const root = path.resolve(__dirname, '../..')
const scopePath = path.join(root, 'docs/02-user-guide/compat/full-1.0-scope.json')
const parityMapPath = path.join(root, 'docs/00-project/PARITY_MAP_FULL_1_0.json')

function fail(message) {
  console.error(`[full1-rc-artifact-collector] ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const args = {
    repository: process.env.GITHUB_REPOSITORY || '',
    runId: 0,
    runAttempt: 0,
    candidateSha: '',
    candidateVersion: '',
    outDir: '',
    indexOut: '',
    provenanceOnly: false,
    artifactWaitSeconds: 30
  }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--repository') args.repository = argv[++i] || ''
    else if (arg === '--run-id') args.runId = Number(argv[++i])
    else if (arg === '--run-attempt') args.runAttempt = Number(argv[++i])
    else if (arg === '--candidate-sha') args.candidateSha = argv[++i] || ''
    else if (arg === '--candidate-version') args.candidateVersion = argv[++i] || ''
    else if (arg === '--out-dir') args.outDir = argv[++i] || ''
    else if (arg === '--index-out') args.indexOut = argv[++i] || ''
    else if (arg === '--provenance-only') args.provenanceOnly = true
    else if (arg === '--artifact-wait-seconds') args.artifactWaitSeconds = Number(argv[++i])
    else fail(`unknown argument: ${arg}`)
  }
  if (!/^[^/]+\/[^/]+$/.test(args.repository)) fail('--repository must be owner/name')
  if (!Number.isInteger(args.runId) || args.runId <= 0) fail('--run-id must be positive')
  if (!Number.isInteger(args.runAttempt) || args.runAttempt <= 0) fail('--run-attempt must be positive')
  if (!/^[0-9a-f]{40}$/i.test(args.candidateSha)) fail('--candidate-sha must be a full SHA')
  if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(args.candidateVersion)) {
    fail('--candidate-version must be semver')
  }
  if (!args.outDir || !args.indexOut) fail('--out-dir and --index-out are required')
  if (!Number.isFinite(args.artifactWaitSeconds) || args.artifactWaitSeconds < 0) {
    fail('--artifact-wait-seconds must be zero or positive')
  }
  return args
}

function expectedArtifacts(context, provenanceOnly = false) {
  const suffix = `${context.runId}-${context.runAttempt}`
  const specs = [{
    id: 'policy',
    role: 'policy',
    workflow: 'Gate Full1 RC / Release Go-No-Go',
    workflowFile: '.github/workflows/gate-full1-rc.yml',
    artifactName: `full1-rc-policy-${suffix}`,
    summaryName: 'full1-rc-policy.summary.json'
  }]
  if (provenanceOnly) return specs
  specs.push({
    id: 'gate3',
    role: 'gate3',
    workflow: 'Gate 3 Full1 / Extended Targets Strict',
    workflowFile: '.github/workflows/gate3-full1-extended.yml',
    artifactName: `full1-gate3-extended-${suffix}`,
    summaryName: 'gate3-full1-extended.summary.json'
  })
  for (const suite of ['misc', 'server', 'threads', 'optimization', 'display']) {
    specs.push({
      id: `suite-${suite}`,
      role: 'suite',
      workflow: 'Full1 / Suite Runners Strict',
      workflowFile: '.github/workflows/full1-suite-runners.yml',
      artifactName: `full1-suite-${suite}-${suffix}`,
      summaryName: `${suite}.summary.json`,
      suite,
      marker: `FULL1_SUITE_${suite.toUpperCase()}:PASS`
    })
  }
  specs.push(
    {
      id: 'macro',
      role: 'macro',
      workflow: 'Macro Runtime Parity (Weekly)',
      workflowFile: '.github/workflows/macro-runtime-parity-weekly.yml',
      artifactName: `macro-runtime-parity-summary-${suffix}`,
      summaryName: 'summary.json'
    },
    {
      id: 'eval',
      role: 'eval',
      workflow: 'Full1 / Eval Native',
      workflowFile: '.github/workflows/full1-eval-native.yml',
      artifactName: `full1-eval-native-${suffix}`,
      summaryName: 'full1-eval-native.summary.json'
    },
    {
      id: 'plugin',
      role: 'plugin',
      workflow: 'Full1 / Plugin Parity',
      workflowFile: '.github/workflows/full1-plugin-parity.yml',
      artifactName: `full1-plugin-parity-summary-${suffix}`,
      summaryName: 'full1-plugin-parity.summary.json'
    },
    {
      id: 'performance',
      role: 'performance',
      workflow: 'Gate Perf Full1 / HXHX vs Haxe',
      workflowFile: '.github/workflows/gate-perf-full1.yml',
      artifactName: `full1-perf-evaluated-${suffix}`,
      summaryName: 'full1-perf-evaluation.json'
    }
  )
  return specs
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function sameMembers(left, right) {
  return Array.isArray(left)
    && Array.isArray(right)
    && left.length === right.length
    && left.every(value => right.includes(value))
}

function requiredGate3Targets() {
  const parityMap = readJson(parityMapPath)
  const entry = (parityMap.entries || []).find(item => item.marker === 'FULL1_GATE3_EXTENDED_TARGETS:PASS')
  if (!entry || !Array.isArray(entry.targets) || entry.targets.length === 0) {
    throw new Error('parity map does not define the required Gate3 target set')
  }
  return entry.targets
}

/** Convert one child summary into the small marker set its role may prove. */
function validateSummary(spec, summary, context) {
  if (spec.role === 'policy') {
    if (summary.schema !== 'full1-rc-policy-evidence.v1') throw new Error('wrong policy schema')
    if (summary.synthetic !== false) throw new Error('policy artifact is synthetic')
    if (!summary.candidate
      || summary.candidate.sha !== context.candidateSha
      || summary.candidate.version !== context.candidateVersion) {
      throw new Error('policy candidate mismatch')
    }
    if (!summary.run
      || summary.run.id !== context.runId
      || summary.run.attempt !== context.runAttempt) {
      throw new Error('policy run identity mismatch')
    }
    if (!sameMembers(summary.markers, rolePolicy.policy.markers)) {
      throw new Error('policy marker set mismatch')
    }
    if (!Array.isArray(summary.results)
      || summary.results.length !== rolePolicy.policy.markers.length
      || !sameMembers(summary.results.map(result => result.marker), rolePolicy.policy.markers)
      || summary.results.some(result => result.exitCode !== 0 || result.markerObserved !== true)) {
      throw new Error('one or more policy guards did not pass')
    }
    return { schema: summary.schema, markers: rolePolicy.policy.markers }
  }
  if (spec.role === 'gate3') {
    if (summary.schema !== 'gate3-extended-summary.v1') throw new Error('wrong Gate3 schema')
    if (summary.strict_no_skip !== true) throw new Error('Gate3 was not strict no-skip')
    if (!Array.isArray(summary.targets_requested) || summary.targets_requested.length === 0) {
      throw new Error('Gate3 requested target list is empty')
    }
    if (!sameMembers(summary.targets_requested, requiredGate3Targets())) {
      throw new Error('Gate3 target set does not match the current parity map')
    }
    if (!sameMembers(summary.targets_requested, summary.targets_ran)) throw new Error('Gate3 target coverage mismatch')
    for (const field of ['targets_skipped', 'targets_failed', 'targets_missing']) {
      if (!Array.isArray(summary[field]) || summary[field].length !== 0) {
        throw new Error(`Gate3 ${field} is not empty`)
      }
    }
    return { schema: summary.schema, markers: rolePolicy.gate3.markers }
  }
  if (spec.role === 'suite') {
    if (summary.schema !== 'full1-upstream-suite-summary.v1') throw new Error('wrong suite schema')
    if (summary.suite !== spec.suite || summary.strict !== true || summary.marker !== spec.marker) {
      throw new Error('suite identity, strict flag, or marker mismatch')
    }
    if (summary.exit_code !== 0 || !Array.isArray(summary.commands)
      || summary.commands.some(command => command.exit_code !== 0 || command.signal)) {
      throw new Error('suite did not complete successfully')
    }
    return { schema: summary.schema, markers: [spec.marker] }
  }
  if (spec.role === 'macro') {
    if (summary.schema !== 'macro-runtime-parity-summary.v3') throw new Error('wrong macro schema')
    if (String(summary.run_id) !== String(context.runId)
      || String(summary.run_attempt) !== String(context.runAttempt)) {
      throw new Error('macro run identity mismatch')
    }
    if (!summary.jobs || !summary.jobs.macro_runtime_parity
      || summary.jobs.macro_runtime_parity.result !== 'success') {
      throw new Error('macro matrix did not succeed')
    }
    if (!summary.jobs.project_macro_module
      || summary.jobs.project_macro_module.result !== 'success') {
      throw new Error('project macro module did not succeed')
    }
    if (!sameMembers(summary.emitted_markers, [
      'MACRO_RUNTIME_PARITY_WEEKLY:PASS',
      'FULL1_MACRO_PARITY:PASS'
    ])) {
      throw new Error('macro summary did not emit its real pass markers')
    }
    return { schema: summary.schema, markers: rolePolicy.macro.markers }
  }
  if (spec.role === 'eval') {
    if (summary.schema !== 'full1-eval-native-summary.v1') throw new Error('wrong eval schema')
    if (summary.marker !== 'FULL1_EVAL_NATIVE:PASS'
      || !summary.eval_context
      || summary.eval_context.stage0_forbidden !== true
      || !summary.result
      || summary.result.exit_code !== 0) {
      throw new Error('native eval evidence did not pass strict stage0-forbidden mode')
    }
    return { schema: summary.schema, markers: rolePolicy.eval.markers }
  }
  if (spec.role === 'plugin') {
    if (summary.schema !== 'full1-plugin-parity-summary.v3') throw new Error('wrong plugin schema')
    if (String(summary.run_id) !== String(context.runId)
      || String(summary.run_attempt) !== String(context.runAttempt)) {
      throw new Error('plugin run identity mismatch')
    }
    if (summary.synthetic !== false || summary.candidate_sha !== context.candidateSha) {
      throw new Error('plugin candidate identity or authenticity mismatch')
    }
    if (!summary.jobs || !summary.jobs.full1_plugin_proofs
      || summary.jobs.full1_plugin_proofs.result !== 'success') {
      throw new Error('plugin proofs did not succeed')
    }
    if (!Array.isArray(summary.errors) || summary.errors.length !== 0) {
      throw new Error('plugin artifact validation contains errors')
    }
    const expectedProofs = [
      ['upstream-to-hxhx', 'full1-plugin-upstream-to-hxhx', 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS'],
      ['hxhx-to-hxhx', 'full1-plugin-hxhx-to-hxhx', 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS'],
      ['upstream-host-adapter', 'full1-plugin-upstream-host-adapter', 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS']
    ]
    if (!Array.isArray(summary.proofs) || summary.proofs.length !== expectedProofs.length) {
      throw new Error('plugin aggregate does not contain every verified proof')
    }
    for (const [id, prefix, marker] of expectedProofs) {
      const proof = summary.proofs.find(item => item.id === id)
      const expectedArtifact = `${prefix}-${context.runId}-${context.runAttempt}`
      if (!proof || proof.verified !== true || proof.artifact_name !== expectedArtifact
        || proof.marker !== marker
        || proof.summary_schema !== 'full1-plugin-proof.v1'
        || !/^[0-9a-f]{64}$/i.test(String(proof.summary_sha256 || ''))
        || !/^[0-9a-f]{64}$/i.test(String(proof.plugin_artifact_sha256 || ''))) {
        throw new Error(`plugin proof ${id} is missing, unverified, or has invalid provenance`)
      }
    }
    if (!sameMembers(summary.required_markers, expectedProofs.map(item => item[2]))) {
      throw new Error('plugin required marker set mismatch')
    }
    if (!sameMembers(summary.emitted_markers, ['FULL1_PLUGIN_PARITY:PASS'])) {
      throw new Error('plugin summary did not emit its real pass marker')
    }
    return { schema: summary.schema, markers: rolePolicy.plugin.markers }
  }
  if (spec.role === 'performance') {
    if (summary.schema !== 'full1-perf-evaluation.v1') throw new Error('wrong performance schema')
    if (summary.decision !== 'pass'
      || summary.marker !== 'FULL1_PERF_PARITY:PASS'
      || !Array.isArray(summary.failures)
      || summary.failures.length !== 0) {
      throw new Error('performance evaluation did not pass')
    }
    return { schema: summary.schema, markers: rolePolicy.performance.markers }
  }
  throw new Error(`unsupported role ${spec.role}`)
}

function findSummary(directory, fileName) {
  const matches = []
  const visit = current => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const resolved = path.join(current, entry.name)
      if (entry.isDirectory()) visit(resolved)
      else if (entry.name === fileName) matches.push(resolved)
    }
  }
  visit(directory)
  if (matches.length !== 1) throw new Error(`expected one ${fileName}, found ${matches.length}`)
  return matches[0]
}

function sha256Buffer(buffer) {
  return `sha256:${crypto.createHash('sha256').update(buffer).digest('hex')}`
}

function safeExtract(zipPath, destination) {
  const listing = spawnSync('unzip', ['-Z1', zipPath], { encoding: 'utf8' })
  if (listing.status !== 0) throw new Error(`cannot list artifact ZIP: ${listing.stderr}`)
  for (const entry of listing.stdout.split(/\r?\n/).filter(Boolean)) {
    const pieces = entry.replace(/\\/g, '/').split('/')
    if (entry.startsWith('/') || pieces.includes('..')) throw new Error(`unsafe ZIP entry: ${entry}`)
  }
  fs.mkdirSync(destination, { recursive: true })
  const extracted = spawnSync('unzip', ['-qq', zipPath, '-d', destination], { encoding: 'utf8' })
  if (extracted.status !== 0) throw new Error(`cannot extract artifact ZIP: ${extracted.stderr}`)
}

async function githubJson(url, token) {
  const response = await fetch(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'hxhx-full1-rc-artifact-collector'
    }
  })
  if (!response.ok) throw new Error(`GitHub API ${response.status}: ${url}`)
  return response.json()
}

async function downloadArtifact(artifact, token) {
  const response = await fetch(artifact.archive_download_url, {
    redirect: 'follow',
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'hxhx-full1-rc-artifact-collector'
    }
  })
  if (!response.ok) throw new Error(`artifact download failed with HTTP ${response.status}`)
  return Buffer.from(await response.arrayBuffer())
}

function wait(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds))
}

/** Allow a short, bounded window for GitHub's artifact list to become current. */
async function listExpectedArtifacts(apiRoot, runId, token, specs, waitSeconds) {
  const deadline = Date.now() + waitSeconds * 1000
  while (true) {
    const payload = await githubJson(`${apiRoot}/actions/runs/${runId}/artifacts?per_page=100`, token)
    const artifacts = payload.artifacts || []
    const names = new Set(artifacts.map(artifact => artifact.name))
    if (specs.every(spec => names.has(spec.artifactName)) || Date.now() >= deadline) return artifacts
    await wait(Math.min(5000, Math.max(1, deadline - Date.now())))
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN
  if (!token) fail('GITHUB_TOKEN or GH_TOKEN is required')
  const apiRoot = `https://api.github.com/repos/${args.repository}`
  const run = await githubJson(`${apiRoot}/actions/runs/${args.runId}`, token)
  if (run.name !== 'Gate Full1 RC / Release Go-No-Go') fail(`unexpected RC workflow: ${run.name}`)
  if (run.head_sha !== args.candidateSha) fail('RC workflow head SHA does not match candidate')
  if (run.run_attempt !== args.runAttempt) fail('RC workflow attempt does not match --run-attempt')

  const context = {
    runId: args.runId,
    runAttempt: args.runAttempt,
    candidateSha: args.candidateSha,
    candidateVersion: args.candidateVersion
  }
  const specs = expectedArtifacts(context, args.provenanceOnly)
  const artifacts = await listExpectedArtifacts(
    apiRoot,
    args.runId,
    token,
    specs,
    args.artifactWaitSeconds
  )
  const sources = []
  const missingArtifacts = []
  const invalidArtifacts = []
  const outDir = path.resolve(args.outDir)
  fs.mkdirSync(outDir, { recursive: true })

  for (const spec of specs) {
    const matches = artifacts.filter(artifact => artifact.name === spec.artifactName)
    if (matches.length === 0) {
      missingArtifacts.push(spec.artifactName)
      continue
    }
    if (matches.length !== 1) {
      invalidArtifacts.push(`${spec.artifactName}: expected one artifact, found ${matches.length}`)
      continue
    }
    const artifact = matches[0]
    try {
      if (artifact.expired) throw new Error('artifact is expired')
      if (!artifact.workflow_run || artifact.workflow_run.id !== args.runId
        || artifact.workflow_run.head_sha !== args.candidateSha) {
        throw new Error('artifact workflow identity mismatch')
      }
      if (!/^sha256:[0-9a-f]{64}$/i.test(String(artifact.digest || ''))) {
        throw new Error('GitHub artifact digest is missing or invalid')
      }
      const bytes = await downloadArtifact(artifact, token)
      const downloadedDigest = sha256Buffer(bytes)
      if (downloadedDigest.toLowerCase() !== artifact.digest.toLowerCase()) {
        throw new Error('downloaded ZIP digest mismatch')
      }
      const zipPath = path.join(outDir, `${artifact.id}.zip`)
      const extractDir = path.join(outDir, String(artifact.id))
      fs.writeFileSync(zipPath, bytes)
      safeExtract(zipPath, extractDir)
      const summaryPath = findSummary(extractDir, spec.summaryName)
      const summary = readJson(summaryPath)
      const validated = validateSummary(spec, summary, context)
      sources.push({
        id: spec.id,
        role: spec.role,
        workflow: spec.workflow,
        workflowFile: spec.workflowFile,
        workflowConclusion: 'success',
        runId: args.runId,
        runAttempt: args.runAttempt,
        headSha: args.candidateSha,
        artifactId: artifact.id,
        artifactName: artifact.name,
        artifactDigest: artifact.digest,
        createdAt: artifact.created_at,
        expiresAt: artifact.expires_at,
        evidenceTier: rolePolicy[spec.role].tier,
        synthetic: false,
        valid: true,
        summary: {
          path: path.relative(extractDir, summaryPath),
          digest: sha256File(summaryPath),
          schema: validated.schema
        },
        markers: validated.markers
      })
    } catch (error) {
      invalidArtifacts.push(`${spec.artifactName}: ${error.message}`)
    }
  }

  const index = {
    schema: 'full1-rc-evidence-index.v1',
    synthetic: false,
    provenanceOnly: args.provenanceOnly,
    candidate: {
      sha: args.candidateSha,
      version: args.candidateVersion
    },
    contract: {
      scopeManifestDigest: sha256File(scopePath),
      parityMapDigest: sha256File(parityMapPath)
    },
    rcWorkflow: {
      runId: args.runId,
      runAttempt: args.runAttempt,
      createdAt: run.created_at
    },
    collectedAt: new Date().toISOString(),
    missingArtifacts,
    invalidArtifacts,
    sources
  }
  const indexOut = path.resolve(args.indexOut)
  fs.mkdirSync(path.dirname(indexOut), { recursive: true })
  fs.writeFileSync(indexOut, `${JSON.stringify(index, null, 2)}\n`)
  console.log(`[full1-rc-artifact-collector] sources=${sources.length} missing=${missingArtifacts.length} invalid=${invalidArtifacts.length}`)
}

if (require.main === module) {
  main().catch(error => fail(error && error.stack ? error.stack : String(error)))
}

module.exports = {
  expectedArtifacts,
  findSummary,
  safeExtract,
  sha256Buffer,
  validateSummary
}
