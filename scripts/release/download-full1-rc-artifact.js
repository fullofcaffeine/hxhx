#!/usr/bin/env node
/**
 * Download the exact Full1 RC decision artifact selected for release.
 *
 * The script checks the GitHub run, run attempt, artifact identity, ZIP digest,
 * and candidate identity before exposing values to the release workflow.
 */

const fs = require('fs')
const path = require('path')
const {
  findSummary,
  safeExtract,
  sha256Buffer
} = require('../ci/full1-rc-artifact-collector')
const { sha256File } = require('../ci/full1-rc-gate')

const workflowName = 'Gate Full1 RC / Release Go-No-Go'
const workflowFile = '.github/workflows/gate-full1-rc.yml'

function fail(message) {
  console.error(`[download-full1-rc-artifact] ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const args = {
    repository: process.env.GITHUB_REPOSITORY || '',
    runId: 0,
    runAttempt: 0,
    outDir: '',
    metadataOut: '',
    githubOutput: '',
    allowNoGo: false
  }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--repository') args.repository = argv[++i] || ''
    else if (arg === '--run-id') args.runId = Number(argv[++i])
    else if (arg === '--run-attempt') args.runAttempt = Number(argv[++i])
    else if (arg === '--out-dir') args.outDir = argv[++i] || ''
    else if (arg === '--metadata-out') args.metadataOut = argv[++i] || ''
    else if (arg === '--github-output') args.githubOutput = argv[++i] || ''
    else if (arg === '--allow-no-go') args.allowNoGo = true
    else fail(`unknown argument: ${arg}`)
  }
  if (!/^[^/]+\/[^/]+$/.test(args.repository)) fail('--repository must be owner/name')
  if (!Number.isInteger(args.runId) || args.runId <= 0) fail('--run-id must be positive')
  if (!Number.isInteger(args.runAttempt) || args.runAttempt <= 0) fail('--run-attempt must be positive')
  if (!args.outDir || !args.metadataOut) fail('--out-dir and --metadata-out are required')
  return args
}

async function githubJson(url, token) {
  const response = await fetch(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'hxhx-full1-rc-release-handoff'
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
      'User-Agent': 'hxhx-full1-rc-release-handoff'
    }
  })
  if (!response.ok) throw new Error(`artifact download failed with HTTP ${response.status}`)
  return Buffer.from(await response.arrayBuffer())
}

/** Prove that the selected ZIP is the decision for the selected RC attempt. */
function validateHandoff(run, artifact, summary, args, now = new Date()) {
  if (run.name !== workflowName || run.path !== workflowFile) {
    throw new Error(`run is not ${workflowFile}`)
  }
  if (run.status !== 'completed') throw new Error('RC workflow is not completed')
  if (!args.allowNoGo && run.conclusion !== 'success') {
    throw new Error(`RC workflow conclusion must be success, received ${run.conclusion}`)
  }
  if (run.run_attempt !== args.runAttempt) throw new Error('RC workflow attempt mismatch')
  if (!/^[0-9a-f]{40}$/i.test(String(run.head_sha || ''))) throw new Error('RC workflow head SHA is invalid')
  if (artifact.name !== `full1-rc-summary-${args.runId}-${args.runAttempt}`) {
    throw new Error('RC artifact name does not match the selected run attempt')
  }
  if (artifact.expired === true) throw new Error('RC artifact is expired')
  if (!/^sha256:[0-9a-f]{64}$/i.test(String(artifact.digest || ''))) {
    throw new Error('RC artifact digest is missing or invalid')
  }
  if (!artifact.workflow_run
    || artifact.workflow_run.id !== args.runId
    || artifact.workflow_run.head_sha !== run.head_sha) {
    throw new Error('RC artifact workflow identity mismatch')
  }
  if (Number.isNaN(Date.parse(artifact.expires_at)) || Date.parse(artifact.expires_at) <= now.getTime()) {
    throw new Error('RC artifact expiration is invalid or has passed')
  }
  if (summary.schema !== 'full1-rc-summary.v2'
    || summary.evidenceTier !== 10
    || summary.synthetic !== false) {
    throw new Error('RC summary is not authentic full1-rc-summary.v2 tier-10 evidence')
  }
  if (!summary.rcWorkflow
    || summary.rcWorkflow.runId !== args.runId
    || summary.rcWorkflow.runAttempt !== args.runAttempt
    || summary.rcWorkflow.file !== workflowFile) {
    throw new Error('RC summary run identity mismatch')
  }
  if (!summary.candidate
    || summary.candidate.sha !== run.head_sha
    || !/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(summary.candidate.version || '')) {
    throw new Error('RC summary candidate identity is invalid')
  }
  const isGo = summary.decision === 'go' && summary.marker === 'FULL1_RELEASE_GO:PASS'
  const isNoGo = summary.decision === 'no-go' && summary.marker === 'FULL1_RELEASE_GO:FAIL'
  if (!isGo && !isNoGo) throw new Error('RC summary decision and marker are inconsistent')
  if (isGo && run.conclusion !== 'success') {
    throw new Error('a successful RC decision requires a successful RC workflow')
  }
  if (!args.allowNoGo && !isGo) {
    throw new Error('RC summary does not authorize publication')
  }
}

function appendOutputs(outputPath, values) {
  if (!outputPath) return
  const lines = Object.entries(values).map(([key, value]) => `${key}=${value}`)
  fs.appendFileSync(outputPath, `${lines.join('\n')}\n`)
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN
  if (!token) fail('GITHUB_TOKEN or GH_TOKEN is required')
  const apiRoot = `https://api.github.com/repos/${args.repository}`
  const run = await githubJson(`${apiRoot}/actions/runs/${args.runId}`, token)
  const artifactPayload = await githubJson(`${apiRoot}/actions/runs/${args.runId}/artifacts?per_page=100`, token)
  const expectedName = `full1-rc-summary-${args.runId}-${args.runAttempt}`
  const matches = (artifactPayload.artifacts || []).filter(artifact => artifact.name === expectedName)
  if (matches.length !== 1) fail(`expected one ${expectedName} artifact, found ${matches.length}`)
  const artifact = matches[0]
  const bytes = await downloadArtifact(artifact, token)
  const downloadedDigest = sha256Buffer(bytes)
  if (downloadedDigest.toLowerCase() !== String(artifact.digest).toLowerCase()) {
    fail('downloaded RC artifact ZIP digest does not match GitHub metadata')
  }

  const outDir = path.resolve(args.outDir)
  const zipPath = path.join(outDir, `${artifact.id}.zip`)
  const extractDir = path.join(outDir, 'extracted')
  fs.mkdirSync(outDir, { recursive: true })
  fs.writeFileSync(zipPath, bytes)
  safeExtract(zipPath, extractDir)
  const summaryPath = findSummary(extractDir, 'full1-rc.summary.json')
  const summary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'))
  validateHandoff(run, artifact, summary, args)

  const metadata = {
    schema: 'full1-rc-release-handoff.v1',
    verified: true,
    downloadedAt: new Date().toISOString(),
    repository: args.repository,
    workflow: {
      name: run.name,
      file: run.path,
      runId: args.runId,
      runAttempt: args.runAttempt,
      conclusion: run.conclusion,
      headSha: run.head_sha
    },
    artifact: {
      id: artifact.id,
      name: artifact.name,
      digest: artifact.digest,
      createdAt: artifact.created_at,
      expiresAt: artifact.expires_at
    },
    summary: {
      path: summaryPath,
      digest: sha256File(summaryPath),
      schema: summary.schema,
      decision: summary.decision,
      marker: summary.marker,
      candidate: summary.candidate
    }
  }
  const metadataOut = path.resolve(args.metadataOut)
  fs.mkdirSync(path.dirname(metadataOut), { recursive: true })
  fs.writeFileSync(metadataOut, `${JSON.stringify(metadata, null, 2)}\n`)
  appendOutputs(args.githubOutput, {
    verified: '1',
    summary_path: summaryPath,
    candidate_sha: summary.candidate.sha,
    candidate_version: summary.candidate.version,
    decision: summary.decision,
    marker: summary.marker,
    source_run_id: args.runId,
    source_run_attempt: args.runAttempt,
    artifact_id: artifact.id,
    artifact_digest: artifact.digest,
    artifact_name: artifact.name,
    workflow_conclusion: run.conclusion,
    metadata_path: metadataOut
  })
  console.log(`[download-full1-rc-artifact] verified ${artifact.name} decision=${summary.decision}`)
}

if (require.main === module) {
  main().catch(error => fail(error && error.stack ? error.stack : String(error)))
}

module.exports = {
  parseArgs,
  validateHandoff
}
