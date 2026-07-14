#!/usr/bin/env node

/**
 * Write and validate the receipt for binaries shared by one strict M7 run.
 *
 * The receipt prevents a speed optimization from silently reusing an artifact
 * from another commit or from a changed checkout. It deliberately records
 * repository-relative paths so downloaded evidence does not leak runner-local
 * absolute paths.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const schema = 'm7-shared-artifacts.v1'
const marker = 'M7_SHARED_ARTIFACTS:PASS'
const commitPattern = /^[0-9a-f]{40}$/
const digestPattern = /^[0-9a-f]{64}$/

function fail(message) {
  throw new Error(message)
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function sha256File(filePath) {
  return sha256(fs.readFileSync(filePath))
}

function runGit(root, args, encoding = 'utf8') {
  const result = spawnSync('git', ['-C', root, ...args], {
    encoding,
    maxBuffer: 64 * 1024 * 1024
  })
  if (result.status !== 0) {
    const stderr = Buffer.isBuffer(result.stderr) ? result.stderr.toString('utf8') : String(result.stderr || '')
    fail(`git ${args.join(' ')} failed: ${stderr.trim() || `exit ${result.status}`}`)
  }
  return result.stdout
}

function trackedFingerprint(root) {
  const commit = String(runGit(root, ['rev-parse', 'HEAD'])).trim()
  const status = String(runGit(root, ['status', '--porcelain', '--untracked-files=no']))
  const diff = runGit(root, ['diff', '--no-ext-diff', '--binary', 'HEAD', '--'], null)

  if (!commitPattern.test(commit)) fail(`git HEAD is not a 40-character commit: ${commit}`)

  return {
    commit,
    trackedSourceClean: status.trim() === '',
    trackedStatusSha256: sha256(status),
    trackedTreeSha256: sha256(diff)
  }
}

function committedTree(root, repoPath) {
  const tree = String(runGit(root, ['rev-parse', `HEAD:${repoPath}`])).trim()
  if (!/^[0-9a-f]{40,64}$/.test(tree)) fail(`cannot identify committed tree for ${repoPath}`)
  return tree
}

function artifactRecord(root, label, artifactPath) {
  const absoluteRoot = path.resolve(root)
  const absolutePath = path.resolve(artifactPath)
  const relativePath = path.relative(absoluteRoot, absolutePath).split(path.sep).join('/')

  if (!relativePath || relativePath === '..' || relativePath.startsWith('../') || path.isAbsolute(relativePath)) {
    fail(`${label} artifact must live inside the repository: ${artifactPath}`)
  }
  if (!relativePath.endsWith('.exe')) fail(`${label} artifact is not a native .exe: ${relativePath}`)
  if (!fs.existsSync(absolutePath)) fail(`${label} artifact does not exist: ${relativePath}`)
  if ((fs.statSync(absolutePath).mode & 0o111) === 0) fail(`${label} artifact is not executable: ${relativePath}`)

  return {
    path: relativePath,
    sha256: sha256File(absolutePath)
  }
}

function buildReport({ root, hxhxBin, macroHostBin }) {
  const fingerprint = trackedFingerprint(root)
  if (!fingerprint.trackedSourceClean) {
    fail('strict M7 shared artifacts require a clean tracked checkout')
  }

  return {
    schema,
    marker,
    createdAt: new Date().toISOString(),
    source: {
      commit: fingerprint.commit,
      trackedSourceClean: fingerprint.trackedSourceClean,
      trackedStatusSha256: fingerprint.trackedStatusSha256,
      trackedTreeSha256: fingerprint.trackedTreeSha256,
      hxhxBootstrapTree: committedTree(root, 'packages/hxhx/bootstrap_out'),
      macroHostBootstrapTree: committedTree(root, 'packages/hxhx-macro-host/bootstrap_out')
    },
    build: {
      stage0Forbidden: true,
      nativeArtifactsRequired: true,
      hxhxBootstrapPreference: 'native'
    },
    artifacts: {
      hxhx: artifactRecord(root, 'hxhx', hxhxBin),
      macroHost: artifactRecord(root, 'macro host', macroHostBin)
    }
  }
}

function validateReport({ root, report, expectedCommit }) {
  const errors = []
  const fingerprint = trackedFingerprint(root)

  if (report?.schema !== schema) errors.push(`schema must be ${schema}`)
  if (report?.marker !== marker) errors.push(`marker must be ${marker}`)
  if (!report?.createdAt || !Number.isFinite(Date.parse(report.createdAt))) errors.push('createdAt must be an ISO timestamp')
  if (!commitPattern.test(String(report?.source?.commit || ''))) errors.push('source.commit must be a 40-character commit')
  if (expectedCommit && report?.source?.commit !== expectedCommit) errors.push('receipt commit does not match expected commit')
  if (report?.source?.commit !== fingerprint.commit) errors.push('receipt commit does not match current checkout')
  if (report?.source?.trackedSourceClean !== true) errors.push('receipt must record a clean tracked checkout')
  if (!fingerprint.trackedSourceClean) errors.push('current tracked checkout is not clean')
  if (!digestPattern.test(String(report?.source?.trackedStatusSha256 || ''))) errors.push('tracked status digest is invalid')
  if (!digestPattern.test(String(report?.source?.trackedTreeSha256 || ''))) errors.push('tracked tree digest is invalid')
  if (report?.source?.trackedStatusSha256 !== fingerprint.trackedStatusSha256) errors.push('tracked checkout status changed after artifact preparation')
  if (report?.source?.trackedTreeSha256 !== fingerprint.trackedTreeSha256) errors.push('tracked checkout content changed after artifact preparation')
  if (report?.source?.hxhxBootstrapTree !== committedTree(root, 'packages/hxhx/bootstrap_out')) errors.push('hxhx bootstrap tree does not match current commit')
  if (report?.source?.macroHostBootstrapTree !== committedTree(root, 'packages/hxhx-macro-host/bootstrap_out')) errors.push('macro-host bootstrap tree does not match current commit')
  if (report?.build?.stage0Forbidden !== true) errors.push('receipt must require stage0-forbidden preparation')
  if (report?.build?.nativeArtifactsRequired !== true) errors.push('receipt must require native artifacts')
  if (report?.build?.hxhxBootstrapPreference !== 'native') errors.push('receipt must record native hxhx bootstrap preference')

  for (const [label, artifact] of Object.entries({ hxhx: report?.artifacts?.hxhx, macroHost: report?.artifacts?.macroHost })) {
    const repoPath = String(artifact?.path || '')
    if (!repoPath || path.isAbsolute(repoPath) || repoPath === '..' || repoPath.startsWith('../') || repoPath.includes('\\')) {
      errors.push(`${label} artifact path must be repository-relative`)
      continue
    }
    if (!repoPath.endsWith('.exe')) errors.push(`${label} artifact must be a native .exe`)
    if (!digestPattern.test(String(artifact?.sha256 || ''))) errors.push(`${label} artifact digest is invalid`)
    const absolutePath = path.resolve(root, repoPath)
    if (!fs.existsSync(absolutePath)) {
      errors.push(`${label} artifact is missing`)
      continue
    }
    if ((fs.statSync(absolutePath).mode & 0o111) === 0) errors.push(`${label} artifact is not executable`)
    if (digestPattern.test(String(artifact?.sha256 || '')) && sha256File(absolutePath) !== artifact.sha256) {
      errors.push(`${label} artifact digest changed after preparation`)
    }
  }

  if (errors.length > 0) fail(errors.join('; '))
  return report
}

function parseArgs(argv) {
  const command = argv[0]
  const options = {}
  for (let index = 1; index < argv.length; index += 1) {
    const key = argv[index]
    if (key === '--quiet') {
      options.quiet = true
      continue
    }
    if (!key.startsWith('--') || index + 1 >= argv.length) fail(`invalid argument: ${key}`)
    options[key.slice(2)] = argv[index + 1]
    index += 1
  }
  return { command, options }
}

function requireOption(options, name) {
  const value = options[name]
  if (!value) fail(`missing --${name}`)
  return value
}

function main(argv) {
  const { command, options } = parseArgs(argv)
  const root = path.resolve(requireOption(options, 'root'))
  const reportPath = path.resolve(requireOption(options, 'report'))

  if (command === 'write') {
    const report = buildReport({
      root,
      hxhxBin: requireOption(options, 'hxhx-bin'),
      macroHostBin: requireOption(options, 'macro-host-bin')
    })
    fs.mkdirSync(path.dirname(reportPath), { recursive: true })
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
    validateReport({ root, report, expectedCommit: report.source.commit })
  } else if (command === 'validate') {
    const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
    validateReport({ root, report, expectedCommit: options['expected-commit'] || '' })
  } else {
    fail('usage: m7-shared-artifacts.js <write|validate> --root <repo> --report <json> [--hxhx-bin <exe> --macro-host-bin <exe>] [--expected-commit <sha>] [--quiet]')
  }

  if (!options.quiet) console.log(marker)
}

if (require.main === module) {
  try {
    main(process.argv.slice(2))
  } catch (error) {
    console.error(`[m7-shared-artifacts] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  buildReport,
  marker,
  schema,
  validateReport
}
