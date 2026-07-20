#!/usr/bin/env node
/**
 * Builds and authenticates the one test-only macro host shared by the Core
 * macro integration shard.
 *
 * The artifact is intentionally request-local. Its immutable manifest binds
 * the executable to the candidate commit, the reviewed entrypoint plan, and
 * its SHA-256 digest. Each consumer verifies that contract before it runs, so
 * reuse cannot turn into an unverified global cache.
 */

const childProcess = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const ARTIFACT_SCHEMA = 'hxhx.macro-host-test-artifact.v1'
const PLAN_SCHEMA = 'hxhx.macro-host-integration-plan.v1'
const PLAN_RELATIVE_PATH = 'scripts/ci/macro-host-integration-plan.json'
const EVIDENCE_RELATIVE_PATH = '.artifacts/core-test/macro-host-integration'

function invariant(condition, message) {
  if (!condition) throw new Error(message)
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function sha256File(filePath) {
  return sha256(fs.readFileSync(filePath))
}

function readJson(filePath, label) {
  let raw
  try {
    raw = fs.readFileSync(filePath, 'utf8')
  } catch (error) {
    throw new Error(`${label} is missing or unreadable at ${filePath}: ${error.message}`)
  }
  try {
    return { raw, value: JSON.parse(raw) }
  } catch (error) {
    throw new Error(`${label} is not valid JSON at ${filePath}: ${error.message}`)
  }
}

function validatePlan(value) {
  invariant(value && value.schema === PLAN_SCHEMA, `macro-host plan schema must be ${PLAN_SCHEMA}`)
  invariant(value.shardId === 'macro-host-integration', 'macro-host plan must own the macro-host-integration shard')
  invariant(Array.isArray(value.extraClassPaths) && value.extraClassPaths.length > 0, 'macro-host plan needs classpaths')
  invariant(value.consumers && typeof value.consumers === 'object', 'macro-host plan needs consumers')

  const consumerIds = Object.keys(value.consumers)
  invariant(consumerIds.length > 0, 'macro-host plan needs at least one consumer')
  const union = []
  const seen = new Set()
  for (const consumerId of consumerIds) {
    const entrypoints = value.consumers[consumerId]
    invariant(Array.isArray(entrypoints) && entrypoints.length > 0, `macro-host consumer ${consumerId} needs entrypoints`)
    invariant(new Set(entrypoints).size === entrypoints.length, `macro-host consumer ${consumerId} repeats an entrypoint`)
    for (const entrypoint of entrypoints) {
      invariant(typeof entrypoint === 'string' && entrypoint.trim() === entrypoint && entrypoint !== '', `${consumerId} has an invalid entrypoint`)
      if (!seen.has(entrypoint)) {
        seen.add(entrypoint)
        union.push(entrypoint)
      }
    }
  }
  invariant(new Set(value.extraClassPaths).size === value.extraClassPaths.length, 'macro-host plan repeats a classpath')
  for (const classPath of value.extraClassPaths) {
    invariant(typeof classPath === 'string' && classPath !== '', 'macro-host plan has an invalid classpath')
  }
  return { ...value, consumerIds, entrypointUnion: union }
}

function loadPlan(repoRoot) {
  const planPath = path.join(repoRoot, PLAN_RELATIVE_PATH)
  const parsed = readJson(planPath, 'macro-host integration plan')
  return {
    path: planPath,
    raw: parsed.raw,
    sha256: sha256(parsed.raw),
    value: validatePlan(parsed.value)
  }
}

function gitOutput(repoRoot, args) {
  const result = childProcess.spawnSync('git', args, { cwd: repoRoot, encoding: 'utf8' })
  invariant(!result.error, `git ${args.join(' ')} could not start: ${result.error && result.error.message}`)
  invariant(result.status === 0, `git ${args.join(' ')} failed: ${(result.stderr || result.stdout).trim()}`)
  return result.stdout.trim()
}

function candidateIdentity(repoRoot) {
  const commit = process.env.GITHUB_SHA || gitOutput(repoRoot, ['rev-parse', 'HEAD'])
  invariant(/^[0-9a-f]{40}$/i.test(commit), `candidate commit must be a 40-character Git SHA, got ${JSON.stringify(commit)}`)
  const status = gitOutput(repoRoot, ['status', '--porcelain', '--untracked-files=all'])
  return {
    commit: commit.toLowerCase(),
    workingTreeDirty: status !== '',
    statusSha256: sha256(status)
  }
}

function normalizeStringArray(value, label) {
  invariant(Array.isArray(value), `${label} must be an array`)
  for (const item of value) invariant(typeof item === 'string' && item !== '', `${label} contains an invalid value`)
  return value
}

function validateArtifactManifest(manifestPath, options = {}) {
  const parsed = readJson(manifestPath, 'shared macro-host manifest')
  const manifest = parsed.value
  invariant(manifest && manifest.schema === ARTIFACT_SCHEMA, `shared macro-host schema must be ${ARTIFACT_SCHEMA}`)
  invariant(manifest.candidate && /^[0-9a-f]{40}$/.test(String(manifest.candidate.commit || '')), 'shared macro-host candidate commit is invalid')
  invariant(typeof manifest.candidate.workingTreeDirty === 'boolean', 'shared macro-host working-tree state is invalid')
  invariant(/^[0-9a-f]{64}$/.test(String(manifest.candidate.statusSha256 || '')), 'shared macro-host status digest is invalid')
  invariant(manifest.plan && /^[0-9a-f]{64}$/.test(String(manifest.plan.sha256 || '')), 'shared macro-host plan digest is invalid')
  invariant(manifest.build && manifest.build.invocationCount === 1, 'shared macro-host build count must be exactly one')
  const entrypoints = normalizeStringArray(manifest.build.entrypoints, 'shared macro-host entrypoints')
  const extraClassPaths = normalizeStringArray(manifest.build.extraClassPaths, 'shared macro-host classpaths')
  invariant(new Set(entrypoints).size === entrypoints.length, 'shared macro-host entrypoints must not repeat')
  if (options.plan) {
    invariant(
      JSON.stringify(entrypoints) === JSON.stringify(options.plan.entrypointUnion),
      'shared macro-host entrypoint union disagrees with the reviewed plan'
    )
    invariant(
      JSON.stringify(extraClassPaths) === JSON.stringify(options.plan.extraClassPaths),
      'shared macro-host classpaths disagree with the reviewed plan'
    )
  }

  if (options.expectedCandidate) {
    invariant(
      manifest.candidate.commit === options.expectedCandidate,
      `shared macro-host candidate is stale: expected ${options.expectedCandidate}, got ${manifest.candidate.commit}`
    )
  }
  if (options.expectedPlanSha256) {
    invariant(
      manifest.plan.sha256 === options.expectedPlanSha256,
      `shared macro-host plan is stale: expected ${options.expectedPlanSha256}, got ${manifest.plan.sha256}`
    )
  }

  invariant(manifest.artifact && typeof manifest.artifact.path === 'string', 'shared macro-host artifact path is missing')
  const executable = path.resolve(manifest.artifact.path)
  if (options.expectedExecutable) {
    invariant(executable === path.resolve(options.expectedExecutable), 'shared macro-host executable path disagrees with its manifest')
  }
  invariant(fs.existsSync(executable), `shared macro-host executable is missing: ${executable}`)
  invariant(fs.statSync(executable).isFile(), `shared macro-host executable is not a file: ${executable}`)
  invariant(/^[0-9a-f]{64}$/.test(String(manifest.artifact.sha256 || '')), 'shared macro-host executable digest is invalid')
  const actualDigest = sha256File(executable)
  invariant(
    actualDigest === manifest.artifact.sha256,
    `shared macro-host executable was modified: expected ${manifest.artifact.sha256}, got ${actualDigest}`
  )
  invariant(fs.statSync(executable).size === manifest.artifact.bytes, 'shared macro-host executable byte count changed')

  if (options.consumerId) {
    const expectedEntrypoints = options.plan && options.plan.consumers[options.consumerId]
    invariant(expectedEntrypoints, `shared macro-host plan has no consumer ${options.consumerId}`)
    for (const entrypoint of expectedEntrypoints) {
      invariant(entrypoints.includes(entrypoint), `shared macro-host is missing ${options.consumerId} entrypoint ${entrypoint}`)
    }
  }
  return { executable, manifest, manifestSha256: sha256(parsed.raw) }
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function prepareSharedMacroHost(repoRoot, shard) {
  const plan = loadPlan(repoRoot)
  invariant(shard.id === plan.value.shardId, `macro-host plan cannot prepare shard ${shard.id}`)
  invariant(
    JSON.stringify(shard.commands) === JSON.stringify(plan.value.consumerIds),
    'macro-host shard commands must exactly match the shared-artifact consumer plan'
  )

  const evidenceRoot = path.join(repoRoot, EVIDENCE_RELATIVE_PATH)
  const manifestPath = path.join(evidenceRoot, 'manifest.json')
  const reportPath = path.join(evidenceRoot, 'report.json')
  const buildRoot = path.join(repoRoot, '.tmp', `hxhx-macro-host-build.core-test-${process.pid}`)
  fs.rmSync(evidenceRoot, { recursive: true, force: true })
  fs.rmSync(buildRoot, { recursive: true, force: true })
  fs.mkdirSync(evidenceRoot, { recursive: true })

  const candidate = candidateIdentity(repoRoot)
  const startedAt = new Date().toISOString()
  const startedMs = Date.now()
  const baseReport = {
    schema: 'hxhx.macro-host-test-report.v1',
    status: 'preparing',
    candidate,
    plan: { path: PLAN_RELATIVE_PATH, sha256: plan.sha256 },
    build: { invocationCount: 1, startedAt },
    consumers: []
  }
  writeJson(reportPath, baseReport)

  let executable
  try {
    const build = childProcess.spawnSync('bash', ['scripts/hxhx/build-hxhx-macro-host.sh'], {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HXHX_MACRO_HOST_ENTRYPOINTS: plan.value.entrypointUnion.join(';'),
        HXHX_MACRO_HOST_EXTRA_CP: plan.value.extraClassPaths.join(':'),
        HXHX_MACRO_HOST_FORCE_STAGE0: '1',
        HXHX_MACRO_HOST_LEASE_PID: String(process.pid),
        HXHX_MACRO_HOST_OUT_DIR: buildRoot
      },
      stdio: ['ignore', 'pipe', 'inherit']
    })
    invariant(!build.error, `shared macro-host build could not start: ${build.error && build.error.message}`)
    invariant(build.status === 0, `shared macro-host build failed with ${build.signal ? `signal ${build.signal}` : `exit ${build.status}`}`)
    const lines = build.stdout.split(/\r?\n/).map(line => line.trim()).filter(Boolean)
    invariant(lines.length > 0, 'shared macro-host build produced no executable path')
    executable = path.resolve(lines[lines.length - 1])
    invariant(fs.existsSync(executable) && fs.statSync(executable).isFile(), `shared macro-host build did not produce ${executable}`)
  } catch (error) {
    writeJson(reportPath, {
      ...baseReport,
      status: 'failed',
      failure: error.message,
      build: { ...baseReport.build, elapsedSeconds: (Date.now() - startedMs) / 1000 }
    })
    fs.rmSync(buildRoot, { recursive: true, force: true })
    throw error
  }

  let manifest
  let report
  try {
    const artifactStat = fs.statSync(executable)
    manifest = {
      schema: ARTIFACT_SCHEMA,
      candidate,
      plan: { path: PLAN_RELATIVE_PATH, sha256: plan.sha256 },
      build: {
        invocationCount: 1,
        forceStage0: true,
        entrypoints: plan.value.entrypointUnion,
        extraClassPaths: plan.value.extraClassPaths,
        elapsedSeconds: (Date.now() - startedMs) / 1000
      },
      artifact: {
        path: executable,
        sha256: sha256File(executable),
        bytes: artifactStat.size
      }
    }
    writeJson(manifestPath, manifest)
    const validated = validateArtifactManifest(manifestPath, {
      expectedCandidate: candidate.commit,
      expectedExecutable: executable,
      expectedPlanSha256: plan.sha256
    })

    report = {
      ...baseReport,
      status: 'running',
      manifest: { path: manifestPath, sha256: validated.manifestSha256 },
      build: { ...manifest.build, startedAt },
      artifact: manifest.artifact,
      consumers: []
    }
    writeJson(reportPath, report)
  } catch (error) {
    writeJson(reportPath, {
      ...baseReport,
      status: 'failed',
      failure: error.message,
      build: { ...baseReport.build, elapsedSeconds: (Date.now() - startedMs) / 1000 }
    })
    fs.rmSync(buildRoot, { recursive: true, force: true })
    throw error
  }

  function verify(consumerId) {
    return validateArtifactManifest(manifestPath, {
      consumerId,
      expectedCandidate: candidate.commit,
      expectedExecutable: executable,
      expectedPlanSha256: plan.sha256,
      plan: plan.value
    })
  }

  return {
    environment: {
      HXHX_MACRO_HOST_EXE: executable,
      HXHX_TEST_MACRO_HOST_CANDIDATE: candidate.commit,
      HXHX_TEST_MACRO_HOST_MANIFEST: manifestPath,
      HXHX_TEST_MACRO_HOST_PLAN_SHA256: plan.sha256
    },
    failConsumer(consumerId, elapsedSeconds, failure) {
      report.consumers.push({ id: consumerId, status: 'failed', elapsedSeconds, failure })
      writeJson(reportPath, report)
    },
    passConsumer(consumerId, elapsedSeconds) {
      verify(consumerId)
      report.consumers.push({ id: consumerId, status: 'passed', elapsedSeconds })
      writeJson(reportPath, report)
    },
    verify,
    finish(status, failure = null) {
      report.status = status
      report.elapsedSeconds = (Date.now() - startedMs) / 1000
      if (failure) report.failure = failure
      report.artifactRetained = false
      fs.rmSync(buildRoot, { recursive: true, force: true })
      writeJson(reportPath, report)
    }
  }
}

function maybePrepareSharedArtifact(repoRoot, shard) {
  if (!shard.preparation) return null
  invariant(shard.preparation.kind === 'shared-macro-host', `unknown shard preparation ${shard.preparation.kind}`)
  invariant(shard.preparation.plan === PLAN_RELATIVE_PATH, 'shared macro-host shard references the wrong plan')
  return prepareSharedMacroHost(repoRoot, shard)
}

module.exports = {
  ARTIFACT_SCHEMA,
  EVIDENCE_RELATIVE_PATH,
  PLAN_RELATIVE_PATH,
  PLAN_SCHEMA,
  loadPlan,
  maybePrepareSharedArtifact,
  prepareSharedMacroHost,
  sha256File,
  validateArtifactManifest,
  validatePlan
}
