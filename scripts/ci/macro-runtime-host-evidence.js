#!/usr/bin/env node

/**
 * Write and validate the candidate-bound host receipt for macro parity CI.
 *
 * The external-host job reuses one executable across several compiler runs.
 * This receipt proves that the file still belongs to the checked-out commit,
 * came from that commit's macro-host snapshot, and speaks the expected RPC
 * protocol before any workload trusts it.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const schema = 'macro-runtime-host-evidence.v1'
const marker = 'MACRO_RUNTIME_EXTERNAL_HOST_ARTIFACT:PASS'
const protocolVersion = 1
const protocolBanner = `hxhx_macro_rpc_v=${protocolVersion}`
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

function artifactRecord(root, artifactPath) {
  const absoluteRoot = path.resolve(root)
  const absolutePath = path.resolve(artifactPath)
  const relativePath = path.relative(absoluteRoot, absolutePath).split(path.sep).join('/')
  if (!relativePath || relativePath === '..' || relativePath.startsWith('../') || path.isAbsolute(relativePath)) {
    fail(`macro host artifact must live inside the repository: ${artifactPath}`)
  }
  if (!relativePath.endsWith('.exe')) fail(`macro host artifact is not a native .exe: ${relativePath}`)
  if (!fs.existsSync(absolutePath) || !fs.statSync(absolutePath).isFile()) {
    fail(`macro host artifact does not exist: ${relativePath}`)
  }
  if ((fs.statSync(absolutePath).mode & 0o111) === 0) fail(`macro host artifact is not executable: ${relativePath}`)
  return { path: relativePath, sha256: sha256File(absolutePath) }
}

function verifyProtocol(artifactPath) {
  const result = spawnSync(path.resolve(artifactPath), [], {
    input: `hello proto=${protocolVersion}\nquit\n`,
    encoding: 'utf8',
    timeout: 10000,
    maxBuffer: 1024 * 1024
  })
  if (result.error) fail(`macro host protocol probe failed: ${result.error.message}`)
  if (result.status !== 0) {
    fail(`macro host protocol probe exited ${result.status}: ${String(result.stderr || '').trim()}`)
  }
  const lines = String(result.stdout || '').split(/\r?\n/).filter(line => line.length > 0)
  if (lines[0] !== protocolBanner) {
    fail(`macro host protocol banner mismatch: expected ${protocolBanner}, got ${lines[0] || '<empty>'}`)
  }
  if (lines[1] !== 'ok') fail(`macro host protocol handshake did not return ok: ${lines[1] || '<empty>'}`)
  return { version: protocolVersion, banner: protocolBanner, handshake: 'ok' }
}

function buildReport({ root, macroHostBin }) {
  const fingerprint = trackedFingerprint(root)
  if (!fingerprint.trackedSourceClean) fail('macro runtime host evidence requires a clean tracked checkout')
  const artifact = artifactRecord(root, macroHostBin)
  return {
    schema,
    marker,
    createdAt: new Date().toISOString(),
    source: {
      commit: fingerprint.commit,
      trackedSourceClean: true,
      trackedStatusSha256: fingerprint.trackedStatusSha256,
      trackedTreeSha256: fingerprint.trackedTreeSha256,
      macroHostBootstrapTree: committedTree(root, 'packages/hxhx-macro-host/bootstrap_out')
    },
    build: {
      product: 'generic-committed-snapshot',
      stage0Forbidden: true,
      lazyAutoBuild: false
    },
    artifact,
    protocol: verifyProtocol(path.resolve(root, artifact.path))
  }
}

function validateReport({ root, report, expectedCommit = '' }) {
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
  if (report?.source?.trackedStatusSha256 !== fingerprint.trackedStatusSha256) errors.push('tracked checkout status changed after preparation')
  if (report?.source?.trackedTreeSha256 !== fingerprint.trackedTreeSha256) errors.push('tracked checkout content changed after preparation')
  if (report?.source?.macroHostBootstrapTree !== committedTree(root, 'packages/hxhx-macro-host/bootstrap_out')) {
    errors.push('macro-host bootstrap tree does not match current commit')
  }
  if (report?.build?.product !== 'generic-committed-snapshot') errors.push('build product must be generic-committed-snapshot')
  if (report?.build?.stage0Forbidden !== true) errors.push('receipt must require stage0-forbidden preparation')
  if (report?.build?.lazyAutoBuild !== false) errors.push('receipt must disable lazy macro-host auto-build')

  const repoPath = String(report?.artifact?.path || '')
  let absolutePath = ''
  if (!repoPath || path.isAbsolute(repoPath) || repoPath === '..' || repoPath.startsWith('../') || repoPath.includes('\\')) {
    errors.push('macro host artifact path must be repository-relative')
  } else {
    absolutePath = path.resolve(root, repoPath)
    if (!repoPath.endsWith('.exe')) errors.push('macro host artifact must be a native .exe')
    if (!digestPattern.test(String(report?.artifact?.sha256 || ''))) errors.push('macro host artifact digest is invalid')
    if (!fs.existsSync(absolutePath) || !fs.statSync(absolutePath).isFile()) {
      errors.push('macro host artifact is missing')
    } else {
      if ((fs.statSync(absolutePath).mode & 0o111) === 0) errors.push('macro host artifact is not executable')
      if (digestPattern.test(String(report?.artifact?.sha256 || '')) && sha256File(absolutePath) !== report.artifact.sha256) {
        errors.push('macro host artifact digest changed after preparation')
      }
    }
  }

  if (report?.protocol?.version !== protocolVersion) errors.push(`protocol version must be ${protocolVersion}`)
  if (report?.protocol?.banner !== protocolBanner) errors.push(`protocol banner must be ${protocolBanner}`)
  if (report?.protocol?.handshake !== 'ok') errors.push('protocol handshake must be ok')
  if (absolutePath && fs.existsSync(absolutePath)) {
    try {
      verifyProtocol(absolutePath)
    } catch (error) {
      errors.push(error.message)
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
    const report = buildReport({ root, macroHostBin: requireOption(options, 'macro-host-bin') })
    fs.mkdirSync(path.dirname(reportPath), { recursive: true })
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
    validateReport({ root, report, expectedCommit: report.source.commit })
  } else if (command === 'validate') {
    const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
    validateReport({ root, report, expectedCommit: options['expected-commit'] || '' })
  } else {
    fail('usage: macro-runtime-host-evidence.js <write|validate> --root <repo> --report <json> [--macro-host-bin <exe>] [--expected-commit <sha>] [--quiet]')
  }
  if (!options.quiet) console.log(marker)
}

if (require.main === module) {
  try {
    main(process.argv.slice(2))
  } catch (error) {
    console.error(`[macro-runtime-host-evidence] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { buildReport, marker, schema, validateReport }
