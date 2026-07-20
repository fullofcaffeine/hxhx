#!/usr/bin/env node
/** Fail-closed fixture coverage for the shared macro-host artifact contract. */

const assert = require('assert')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const {
  ARTIFACT_SCHEMA,
  PLAN_SCHEMA,
  macroHostBuildLeasePath,
  macroHostGeneratedInputPath,
  validateArtifactManifest,
  validatePlan
} = require('./macro-host-test-artifact')

const candidate = 'a'.repeat(40)
const planSha256 = 'b'.repeat(64)
const consumerId = 'test:consumer'
const entrypoint = 'demo.Macros.run()'

function digest(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function expectFailure(label, snippet, callback) {
  let semanticTestRan = false
  assert.throws(
    () => {
      callback()
      semanticTestRan = true
    },
    error => error.message.includes(snippet),
    `${label} did not report ${JSON.stringify(snippet)}`
  )
  assert.strictEqual(semanticTestRan, false, `${label} reached the semantic test`)
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-macro-host-artifact-'))
  try {
    const buildRoot = path.join(tempRoot, 'generated-output')
    const buildLease = macroHostBuildLeasePath(buildRoot)
    const generatedInput = macroHostGeneratedInputPath(buildRoot)
    assert.strictEqual(path.relative(buildRoot, buildLease).startsWith('..'), true, 'build lease must remain outside generated compiler output')
    assert.strictEqual(path.relative(buildRoot, generatedInput).startsWith('..'), true,
      'generated Haxe inputs must remain outside generated compiler output')

    const executable = path.join(tempRoot, 'macro-host.exe')
    const manifestPath = path.join(tempRoot, 'manifest.json')
    const executableBody = Buffer.from('fixture macro host\n')
    fs.writeFileSync(executable, executableBody)

    const plan = validatePlan({
      schema: PLAN_SCHEMA,
      shardId: 'macro-host-integration',
      extraClassPaths: ['test/fixtures'],
      consumers: { [consumerId]: [entrypoint] }
    })
    const validManifest = {
      schema: ARTIFACT_SCHEMA,
      candidate: { commit: candidate, workingTreeDirty: false, statusSha256: digest('') },
      plan: { sha256: planSha256 },
      build: {
        invocationCount: 1,
        entrypoints: [entrypoint],
        extraClassPaths: ['test/fixtures']
      },
      artifact: {
        path: executable,
        sha256: digest(executableBody),
        bytes: executableBody.length
      }
    }
    const writeManifest = value => fs.writeFileSync(manifestPath, `${JSON.stringify(value, null, 2)}\n`)
    const verify = () => validateArtifactManifest(manifestPath, {
      consumerId,
      expectedCandidate: candidate,
      expectedExecutable: executable,
      expectedPlanSha256: planSha256,
      plan
    })

    writeManifest(validManifest)
    assert.strictEqual(verify().executable, executable)

    fs.rmSync(manifestPath)
    expectFailure('missing manifest', 'missing or unreadable', verify)

    writeManifest(validManifest)
    fs.rmSync(executable)
    expectFailure('missing executable', 'executable is missing', verify)

    fs.writeFileSync(executable, executableBody)
    writeManifest({ ...validManifest, candidate: { ...validManifest.candidate, commit: 'c'.repeat(40) } })
    expectFailure('stale candidate', 'candidate is stale', verify)

    writeManifest({
      ...validManifest,
      build: { ...validManifest.build, entrypoints: ['demo.Macros.wrong()'] }
    })
    expectFailure('wrong entrypoint', 'entrypoint union disagrees', verify)

    writeManifest(validManifest)
    fs.appendFileSync(executable, 'modified\n')
    expectFailure('modified executable', 'executable was modified', verify)

    fs.writeFileSync(executable, executableBody)
    writeManifest({ ...validManifest, build: { ...validManifest.build, invocationCount: 2 } })
    expectFailure('multiple builds', 'build count must be exactly one', verify)
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true })
  }
  console.log('MACRO_HOST_TEST_ARTIFACT_CONTRACT:PASS')
}

main()
