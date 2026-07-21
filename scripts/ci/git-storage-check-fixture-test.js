#!/usr/bin/env node
/** Prove the local Git storage doctor stays read-only and fail-closed. */

'use strict'

const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const repositoryRoot = path.resolve(__dirname, '../..')
const checker = path.join(repositoryRoot, 'scripts/dev/check-git-storage.js')
const fixtureRoots = []

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options })
  if (result.error) throw result.error
  return result
}

function makeFixture(name) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), `hxhx-git-storage-${name}-`))
  fixtureRoots.push(root)
  const initialized = runCommand('git', ['init', '--quiet', root])
  assert(initialized.status === 0, `could not initialize ${name} fixture: ${initialized.stderr}`)
  return root
}

function run(root, extraArgs = [], extraEnv = {}) {
  return runCommand(process.execPath, [checker, '--root', root, ...extraArgs], {
    cwd: repositoryRoot,
    env: { ...process.env, ...extraEnv },
  })
}

function runGit(root, args, input) {
  const result = runCommand('git', ['-C', root, ...args], { input })
  assert(result.status === 0, `Git fixture setup failed: ${result.stderr}`)
  return result
}

function fingerprintTree(root) {
  const hash = crypto.createHash('sha256')

  function visit(directory, prefix) {
    const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) =>
      left.name.localeCompare(right.name),
    )
    for (const entry of entries) {
      const relative = path.join(prefix, entry.name)
      const absolute = path.join(directory, entry.name)
      hash.update(`${entry.isDirectory() ? 'd' : entry.isSymbolicLink() ? 'l' : 'f'}\0${relative}\0`)
      if (entry.isDirectory()) visit(absolute, relative)
      else if (entry.isSymbolicLink()) hash.update(fs.readlinkSync(absolute))
      else hash.update(fs.readFileSync(absolute))
    }
  }

  visit(root, '')
  return hash.digest('hex')
}

try {
  const absentRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-git-storage-absent-'))
  fixtureRoots.push(absentRoot)
  const absent = run(absentRoot)
  assert(absent.status === 0, 'a non-repository directory should not fail the diagnostic')
  assert(absent.stdout.includes('GIT_STORAGE_CHECK:SKIP'), 'a non-repository directory should emit the skip marker')

  const healthyRoot = makeFixture('healthy')
  runGit(healthyRoot, ['config', '--local', 'gc.cruftPacks', 'true'])
  const healthyBefore = fingerprintTree(path.join(healthyRoot, '.git'))
  const healthy = run(healthyRoot, ['--json'])
  assert(healthy.status === 0, `a healthy repository should pass: ${healthy.stderr}`)
  const healthyReport = JSON.parse(healthy.stdout)
  assert(healthyReport.status === 'pass', 'the JSON report should identify a healthy repository')
  assert(healthyReport.cruftPacks === true, 'the JSON report should expose the local cruft-pack policy')
  assert(
    healthyReport.looseSizeReviewKiB === 256 * 1024,
    'the JSON report should expose the project byte-based review threshold',
  )
  assert(
    healthyReport.filesystemAvailableKiB === null || healthyReport.filesystemAvailableKiB >= 0,
    'the JSON report should expose available filesystem space when the host provides it',
  )
  assert(
    fingerprintTree(path.join(healthyRoot, '.git')) === healthyBefore,
    'the diagnostic must not change a healthy Git directory',
  )

  const logRoot = makeFixture('gc-log')
  const gcLogPath = path.join(logRoot, '.git', 'gc.log')
  fs.writeFileSync(gcLogPath, 'fixture automatic-maintenance failure\n')
  const logBefore = fingerprintTree(path.join(logRoot, '.git'))
  const logWarning = run(logRoot)
  assert(logWarning.status === 2, 'a retained gc.log should require review')
  assert(logWarning.stderr.includes('reasons=gc_log'), 'the warning should identify gc.log')
  assert(fs.readFileSync(gcLogPath, 'utf8') === 'fixture automatic-maintenance failure\n', 'the doctor must not clear gc.log')
  assert(
    fingerprintTree(path.join(logRoot, '.git')) === logBefore,
    'the diagnostic must not change a warned Git directory',
  )

  const looseRoot = makeFixture('loose')
  runGit(looseRoot, ['config', '--local', 'gc.auto', '1'])
  runGit(looseRoot, ['hash-object', '-w', '--stdin'], 'first loose fixture\n')
  runGit(looseRoot, ['hash-object', '-w', '--stdin'], 'second loose fixture\n')
  const looseBefore = fingerprintTree(path.join(looseRoot, '.git'))
  const looseWarning = run(looseRoot)
  assert(looseWarning.status === 2, 'loose objects above the configured threshold should require review')
  assert(looseWarning.stderr.includes('loose_object_threshold'), 'the warning should identify the loose-object threshold')
  assert(
    fingerprintTree(path.join(looseRoot, '.git')) === looseBefore,
    'the diagnostic must not repack or prune loose objects',
  )

  const byteHeavyRoot = makeFixture('byte-heavy')
  const byteHeavyGit = path.join(byteHeavyRoot, 'fake-git.js')
  fs.writeFileSync(
    byteHeavyGit,
    `#!/usr/bin/env node
const args = process.argv.slice(2)
if (args.includes('--version')) console.log('git version fixture')
else if (args.includes('--absolute-git-dir')) console.log(process.env.HXHX_FAKE_GIT_DIR)
else if (args.includes('count-objects')) console.log([
  'count: 2',
  'size: 300000',
  'in-pack: 0',
  'packs: 0',
  'size-pack: 0',
  'prune-packable: 0',
  'garbage: 0',
  'size-garbage: 0',
].join('\\n'))
else if (args.includes('config')) process.exitCode = 1
else process.exitCode = 1
`,
  )
  fs.chmodSync(byteHeavyGit, 0o755)
  const byteHeavyBefore = fingerprintTree(path.join(byteHeavyRoot, '.git'))
  const byteHeavy = run(byteHeavyRoot, [], {
    HXHX_GIT_STORAGE_GIT_BIN: byteHeavyGit,
    HXHX_FAKE_GIT_DIR: path.join(byteHeavyRoot, '.git'),
  })
  assert(byteHeavy.status === 2, 'a few byte-heavy loose objects should require review')
  assert(
    byteHeavy.stderr.includes('loose_object_bytes'),
    'the warning should explain that loose-object bytes exceeded the project limit',
  )
  assert(
    byteHeavy.stderr.includes('large unpacked file-history objects'),
    'the warning should explain the practical problem before relying on Git terminology',
  )
  assert(
    fingerprintTree(path.join(byteHeavyRoot, '.git')) === byteHeavyBefore,
    'the byte-based warning must not repack or prune loose objects',
  )

  const disabledRoot = makeFixture('disabled')
  runGit(disabledRoot, ['config', '--local', 'gc.auto', '0'])
  const disabled = run(disabledRoot)
  assert(disabled.status === 2, 'disabled automatic maintenance should require review')
  assert(disabled.stderr.includes('automatic_gc_disabled'), 'the warning should identify disabled automatic maintenance')

  const malformedRoot = makeFixture('malformed')
  const fakeGit = path.join(malformedRoot, 'fake-git.js')
  fs.writeFileSync(
    fakeGit,
    `#!/usr/bin/env node
const args = process.argv.slice(2)
if (args.includes('--version')) console.log('git version fixture')
else if (args.includes('--absolute-git-dir')) console.log(process.env.HXHX_FAKE_GIT_DIR)
else if (args.includes('count-objects')) console.log('count: not-a-number')
else process.exitCode = 1
`,
  )
  fs.chmodSync(fakeGit, 0o755)
  const malformed = run(malformedRoot, [], {
    HXHX_GIT_STORAGE_GIT_BIN: fakeGit,
    HXHX_FAKE_GIT_DIR: path.join(malformedRoot, '.git'),
  })
  assert(malformed.status === 1, 'malformed Git object counts should fail closed')
  assert(malformed.stderr.includes('did not report count'), 'the malformed count failure should identify the missing field')

  console.log('GIT_STORAGE_CHECK_FIXTURE:PASS')
} finally {
  for (const root of fixtureRoots) fs.rmSync(root, { recursive: true, force: true })
}
