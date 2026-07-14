#!/usr/bin/env node

/**
 * Exercise the external macro-host receipt, workflow contract, and recursion guard.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { buildReport, marker, schema, validateReport } = require('./macro-runtime-host-evidence.js')

const root = path.resolve(__dirname, '..', '..')
const workflow = path.join(root, '.github', 'workflows', 'macro-runtime-parity-weekly.yml')
const buildScript = path.join(root, 'scripts', 'hxhx', 'build-hxhx-macro-host.sh')
const unitRunner = path.join(root, 'scripts', 'hxhx', 'run-upstream-unit-macro-stage3-no-emit.sh')
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-macro-runtime-host-evidence-'))

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || fixture,
    env: options.env || process.env,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024
  })
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')} failed:\n${result.stdout}\n${result.stderr}`)
  return result.stdout
}

function write(filePath, content, mode) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content)
  if (mode) fs.chmodSync(filePath, mode)
}

function expectFailure(label, action, pattern) {
  try {
    action()
  } catch (error) {
    if (!pattern.test(error.message)) throw new Error(`${label} failed for the wrong reason: ${error.message}`)
    return
  }
  throw new Error(`${label} unexpectedly passed`)
}

const validHost = [
  '#!/usr/bin/env bash',
  'set -eu',
  "printf 'hxhx_macro_rpc_v=1\\n'",
  'IFS= read -r hello',
  '[ "$hello" = "hello proto=1" ]',
  "printf 'ok\\n'",
  'IFS= read -r quit',
  '[ "$quit" = "quit" ]'
].join('\n') + '\n'

try {
  run('git', ['init', '-q'])
  run('git', ['config', 'user.email', 'macro-host-fixture@example.invalid'])
  run('git', ['config', 'user.name', 'Macro Host Fixture'])
  write(path.join(fixture, 'packages', 'hxhx-macro-host', 'bootstrap_out', 'dune'), '(executable (name out))\n')
  write(path.join(fixture, 'tracked.txt'), 'clean\n')
  run('git', ['add', '.'])
  run('git', ['commit', '-q', '-m', 'fixture'])

  const host = path.join(fixture, '.artifacts', 'macro-runtime', 'hxhx-macro-host.exe')
  write(host, validHost, 0o755)
  const report = buildReport({ root: fixture, macroHostBin: host })
  const commit = run('git', ['rev-parse', 'HEAD']).trim()
  validateReport({ root: fixture, report, expectedCommit: commit })
  if (report.schema !== schema || report.marker !== marker) throw new Error('valid receipt lost schema or marker')
  if (path.isAbsolute(report.artifact.path)) throw new Error('receipt leaked an absolute artifact path')
  if (report.protocol.handshake !== 'ok') throw new Error('receipt did not record the real protocol handshake')

  fs.appendFileSync(host, '# changed\n')
  expectFailure('changed artifact', () => validateReport({ root: fixture, report, expectedCommit: commit }), /digest changed/)
  write(host, validHost, 0o755)

  write(path.join(fixture, 'tracked.txt'), 'dirty\n')
  expectFailure('dirty checkout', () => validateReport({ root: fixture, report, expectedCommit: commit }), /not clean|content changed|status changed/)
  run('git', ['checkout', '--', 'tracked.txt'])

  expectFailure('cross-commit receipt', () => validateReport({ root: fixture, report, expectedCommit: '0'.repeat(40) }), /expected commit/)
  expectFailure('legacy schema', () => validateReport({ root: fixture, report: { ...report, schema: 'macro-runtime-host-evidence.v0' }, expectedCommit: commit }), /schema/)
  expectFailure('stage0-enabled receipt', () => validateReport({
    root: fixture,
    report: { ...report, build: { ...report.build, stage0Forbidden: false } },
    expectedCommit: commit
  }), /stage0-forbidden/)
  expectFailure('lazy auto-build receipt', () => validateReport({
    root: fixture,
    report: { ...report, build: { ...report.build, lazyAutoBuild: true } },
    expectedCommit: commit
  }), /disable lazy/)

  write(host, '#!/usr/bin/env bash\nprintf "wrong-protocol\\n"\n', 0o755)
  expectFailure('wrong protocol', () => buildReport({ root: fixture, macroHostBin: host }), /banner mismatch/)

  const recursive = spawnSync('bash', [buildScript], {
    cwd: root,
    env: { ...process.env, HXHX_MACRO_HOST_BUILD_DEPTH: '1' },
    encoding: 'utf8'
  })
  if (recursive.status !== 2) throw new Error(`nested macro-host build exited ${recursive.status}, expected 2`)
  if (!`${recursive.stdout}\n${recursive.stderr}`.includes('cannot start another macro-host build')) {
    throw new Error('nested macro-host build did not explain the recursion failure')
  }

  const workflowSource = fs.readFileSync(workflow, 'utf8')
  for (const expected of [
    "HXHX_MACRO_HOST_AUTO_BUILD: '0'",
    "HXHX_FORBID_STAGE0: '1'",
    'Prepare one external macro-host artifact',
    'macro-runtime-host-evidence.js write',
    'Haxe-authored project macro module',
    'npm run test:macro-runtime:project-module',
    'full1-macro-parity-evidence.js',
    'Download in-process macro proof',
    'Download external-host macro proof',
    'Download project macro proof',
    'macro_artifact_verification=',
    marker
  ]) {
    if (!workflowSource.includes(expected)) throw new Error(`macro parity workflow is missing: ${expected}`)
  }
  const validations = workflowSource.match(/macro-runtime-host-evidence\.js validate/g) || []
  if (validations.length < 4) throw new Error('macro parity workflow must revalidate the host before every workload and final marker')

  const unitSource = fs.readFileSync(unitRunner, 'utf8')
  if (!unitSource.includes('HXHX_MACRO_HOST_AUTO_BUILD="$MACRO_HOST_AUTO_BUILD"')) {
    throw new Error('unit macro runner must respect the caller-selected auto-build policy')
  }

  console.log('MACRO_RUNTIME_HOST_EVIDENCE_FIXTURES:PASS')
} finally {
  fs.rmSync(fixture, { recursive: true, force: true })
}
