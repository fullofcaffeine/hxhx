#!/usr/bin/env node
/** Prove that the native macro-host build cannot bypass a peer repository's lease. */
'use strict'

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn, spawnSync } = require('child_process')
const { acquireLease, releaseLease, readLeaseSnapshot } = require('../hxhx/local-heavy-run-lease.js')

const repoRoot = path.resolve(__dirname, '../..')
const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'macro-host-heavy-lease-'))
const scriptsDir = path.join(fixtureRoot, 'scripts/hxhx')
const binDir = path.join(fixtureRoot, 'bin')
const leasePath = path.join(fixtureRoot, 'peer.lease.json')
const marker = path.join(fixtureRoot, 'native-build-started')
let peer

async function main() {
try {
  fs.mkdirSync(scriptsDir, { recursive: true })
  fs.mkdirSync(binDir)
  fs.mkdirSync(path.join(fixtureRoot, 'packages/hxhx-macro-host/bootstrap_out'), { recursive: true })
  for (const name of ['build-hxhx-macro-host.sh', 'with-heavy-run-lease.js', 'local-heavy-run-lease.js']) {
    fs.copyFileSync(path.join(repoRoot, 'scripts/hxhx', name), path.join(scriptsDir, name))
  }
  fs.writeFileSync(path.join(binDir, 'ocamlc'), '#!/usr/bin/env bash\nexit 0\n', { mode: 0o755 })
  fs.writeFileSync(path.join(binDir, 'dune'), `#!/usr/bin/env bash
set -euo pipefail
printf 'native build started\n' >> "$MACRO_HOST_STUB_MARKER"
if [ "$MACRO_HOST_STUB_EXIT" != 0 ]; then exit "$MACRO_HOST_STUB_EXIT"; fi
mkdir -p _build/default
printf '#!/usr/bin/env bash\nexit 0\n' > _build/default/out.exe
chmod +x _build/default/out.exe
`, { mode: 0o755 })

  fs.writeFileSync(path.join(binDir, 'haxe'), `#!${process.execPath}
const fs = require('fs')
const path = require('path')
const stage3 = path.basename(process.argv[1]) === 'hxhx'
fs.appendFileSync(process.env.MACRO_HOST_STUB_MARKER, (stage3 ? 'stage3' : 'stage0') + ' native build started\\n')
if (process.env.MACRO_HOST_STUB_HOLD === '1') {
  const child = require('child_process').spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'])
  fs.writeFileSync(process.env.MACRO_HOST_STUB_CHILD_PID, String(child.pid))
  process.stderr.write('NATIVE_CHILD_READY\\n')
  setInterval(() => {}, 1000)
}
const requestedExit = stage3 ? process.env.MACRO_HOST_STUB_STAGE3_EXIT : process.env.MACRO_HOST_STUB_EXIT
if (requestedExit !== '0') process.exit(Number(requestedExit))
const output = stage3 ? process.argv[process.argv.indexOf('--hxhx-out') + 1] : process.argv.find(arg => arg.startsWith('ocaml_output=')).slice('ocaml_output='.length)
fs.mkdirSync(path.join(output, '_build/default'), { recursive: true })
fs.writeFileSync(path.join(output, '_build/default/out.exe'), '#!/bin/sh\\nexit 0\\n', { mode: 0o755 })
`, { mode: 0o755 })
  fs.copyFileSync(path.join(binDir, 'haxe'), path.join(binDir, 'hxhx'))
  fs.chmodSync(path.join(binDir, 'hxhx'), 0o755)
  fs.writeFileSync(path.join(scriptsDir, 'build-hxhx.sh'), `#!/usr/bin/env bash
printf '%s\\n' "$MACRO_HOST_STUB_HXHX"
`, { mode: 0o755 })
  fs.mkdirSync(path.join(fixtureRoot, 'std'))
  const env = {
      ...process.env,
      CI: '',
      GITHUB_ACTIONS: '',
      PATH: `${binDir}${path.delimiter}${process.env.PATH}`,
      HXHX_HEAVY_RUN_LEASE_FILE: leasePath,
      HAXE_FAMILY_HEAVY_RUN_LEASE_OWNER_PID: '',
      HXHX_HEAVY_RUN_LEASE_OWNER_PID: '',
      HAXE_FAMILY_HEAVY_RUN_WAIT_SECONDS: '0.05',
      HAXE_FAMILY_HEAVY_RUN_POLL_SECONDS: '0.01',
      HXHX_MACRO_HOST_LEASE_PID: '',
      HXHX_MACRO_HOST_BUILD_DEPTH: '0',
      HXHX_MACRO_HOST_FORCE_STAGE0: '',
      HXHX_MACRO_HOST_ENTRYPOINTS: '',
      HXHX_MACRO_HOST_EXTRA_CP: '',
      MACRO_HOST_STUB_MARKER: marker,
      MACRO_HOST_STUB_EXIT: '0',
      MACRO_HOST_STUB_STAGE3_EXIT: '0',
      MACRO_HOST_STUB_HXHX: path.join(binDir, 'hxhx'),
      HAXE_BIN: path.join(binDir, 'haxe'),
      MACRO_HOST_STUB_HOLD: '',
      MACRO_HOST_STUB_CHILD_PID: path.join(fixtureRoot, 'native-child.pid'),
  }
  function run(overrides = {}) {
    const result = spawnSync('bash', [path.join(scriptsDir, 'build-hxhx-macro-host.sh')], {
      cwd: fixtureRoot, encoding: 'utf8', timeout: 10000, env: { ...env, ...overrides },
    })
    assert.ifError(result.error)
    return result
  }
  function holdPeer() {
    peer = acquireLease({ leasePath, ownerPid: process.pid, repository: 'peer-haxe-repository', label: 'peer-native-build' })
    assert.strictEqual(peer.status, 'acquired')
  }
  function dropPeer() {
    releaseLease({ leasePath, ownerPid: process.pid, ownerToken: peer.record.owner.token })
    peer = null
  }
  holdPeer()
  const result = run()
  assert.ifError(result.error)
  assert.strictEqual(result.status, 75, `a peer lease must prevent native compilation: ${result.stdout} ${result.stderr}`)
  assert.strictEqual(fs.existsSync(marker), false, 'the native tool must not start while a peer owns the lease')
  assert.strictEqual(readLeaseSnapshot(leasePath).record.owner.token, peer.record.owner.token)
  const nested = run({ HAXE_FAMILY_HEAVY_RUN_LEASE_OWNER_PID: String(process.pid) })
  assert.strictEqual(nested.status, 0, nested.stderr)
  assert.match(nested.stderr, /HAXE_FAMILY_HEAVY_RUN:REENTRANT/)
  assert.strictEqual(readLeaseSnapshot(leasePath).record.owner.token, peer.record.owner.token, 'nested builds retain the outer owner')
  dropPeer()

  const expectedPath = path.join(fixtureRoot, 'packages/hxhx-macro-host/bootstrap_out/_build/default/out.exe')
  const direct = run()
  assert.strictEqual(direct.status, 0, direct.stderr)
  assert.strictEqual(direct.stdout, `${expectedPath}\n`, 'stdout is only the native executable path')
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing')
  const failed = run({ MACRO_HOST_STUB_EXIT: '23' })
  assert.strictEqual(failed.status, 23, failed.stderr)
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing', 'failed builds release their scheduling lease')

  fs.rmSync(marker)
  holdPeer()
  let sawWait = false
  let startedWhileWaiting = false
  const queued = await new Promise((resolve, reject) => {
    const child = spawn('bash', [path.join(scriptsDir, 'build-hxhx-macro-host.sh')], {
      cwd: fixtureRoot, detached: true, env: { ...env, HAXE_FAMILY_HEAVY_RUN_WAIT_SECONDS: '3' },
    })
    let stdout = ''
    let stderr = ''
    let timedOut = false
    const timeout = setTimeout(() => {
      timedOut = true
      process.kill(-child.pid, 'SIGTERM')
    }, 5000)
    child.stdout.on('data', chunk => { stdout += chunk })
    child.stderr.on('data', chunk => {
      stderr += chunk
      if (!sawWait && stderr.includes('HAXE_FAMILY_HEAVY_RUN:WAITING')) {
        sawWait = true
        startedWhileWaiting = fs.existsSync(marker)
        dropPeer()
      }
    })
    child.on('error', error => { clearTimeout(timeout); reject(error) })
    child.on('close', status => {
      clearTimeout(timeout)
      if (timedOut) reject(new Error('queued fixture exceeded its deadline'))
      else resolve({ status, stdout, stderr })
    })
  })
  assert(sawWait, 'the native build must observe the peer owner before it starts')
  assert.strictEqual(startedWhileWaiting, false, 'waiting must happen before native compilation')
  assert.strictEqual(queued.status, 0, queued.stderr)
  assert.strictEqual(queued.stdout, `${expectedPath}\n`)
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing')
  const dynamicOutput = path.join(fixtureRoot, '.tmp/dynamic-host')
  const dynamicEnv = {
    HXHX_MACRO_HOST_FORCE_STAGE0: '1',
    HXHX_MACRO_HOST_ENTRYPOINTS: 'Fixture.run()',
    HXHX_MACRO_HOST_OUT_DIR: dynamicOutput,
  }
  fs.rmSync(marker)
  holdPeer()
  const blockedDynamic = run(dynamicEnv)
  assert.strictEqual(blockedDynamic.status, 75, blockedDynamic.stderr)
  assert.strictEqual(fs.existsSync(marker), false)
  assert.strictEqual(fs.existsSync(`${dynamicOutput}.hxhx-macro-host-input`), false, 'queued stage0 failure removes generated inputs')
  dropPeer()
  const failedDynamic = run({ ...dynamicEnv, MACRO_HOST_STUB_EXIT: '23' })
  assert.strictEqual(failedDynamic.status, 23, failedDynamic.stderr)
  assert.strictEqual(fs.existsSync(`${dynamicOutput}.hxhx-macro-host-input`), false, 'failed stage0 compilation removes generated inputs')
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing')
  const directDynamic = run(dynamicEnv)
  assert.strictEqual(directDynamic.status, 0, directDynamic.stderr)
  assert.strictEqual(directDynamic.stdout, `${dynamicOutput}/_build/default/out.exe\n`)
  assert.strictEqual(fs.existsSync(`${dynamicOutput}.hxhx-macro-host-input`), false)
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing')
  const stage3Env = {
    ...dynamicEnv,
    HXHX_MACRO_HOST_FORCE_STAGE0: '',
    HXHX_MACRO_HOST_PREFER_HXHX: '1',
    HAXE_STD_PATH: path.join(fixtureRoot, 'std'),
  }
  for (const status of [75, 129, 130, 143]) {
    fs.rmSync(marker)
    const stopped = run({ ...stage3Env, MACRO_HOST_STUB_STAGE3_EXIT: String(status) })
    assert.strictEqual(stopped.status, status, stopped.stderr)
    assert.strictEqual(fs.readFileSync(marker, 'utf8'), 'stage3 native build started\n', 'a scheduling stop must not fall back to stage0')
    assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing')
    assert.strictEqual(fs.existsSync(`${dynamicOutput}.hxhx-macro-host-input`), false)
  }
  let cancellationRequested = false
  const cancelled = await new Promise((resolve, reject) => {
    const child = spawn('bash', [path.join(scriptsDir, 'build-hxhx-macro-host.sh')], {
      cwd: fixtureRoot, detached: true, env: { ...env, ...dynamicEnv, MACRO_HOST_STUB_HOLD: '1' },
    })
    let stderr = ''
    const timeout = setTimeout(() => { process.kill(-child.pid, 'SIGTERM') }, 5000)
    child.stdout.resume()
    child.stderr.on('data', chunk => {
      stderr += chunk
      if (!cancellationRequested && stderr.includes('NATIVE_CHILD_READY')) {
        cancellationRequested = true
        process.kill(-child.pid, 'SIGTERM')
      }
    })
    child.on('error', error => { clearTimeout(timeout); reject(error) })
    child.on('close', (status, signal) => { clearTimeout(timeout); resolve({ status, signal, stderr }) })
  })
  assert(cancellationRequested, 'cancellation must exercise a running native child')
  assert(cancelled.signal === 'SIGTERM' || cancelled.status === 143, cancelled.stderr)
  const descendantPid = Number(fs.readFileSync(env.MACRO_HOST_STUB_CHILD_PID, 'utf8'))
  function alive(pid) {
    try { process.kill(pid, 0); return true } catch (error) { if (error.code === 'ESRCH') return false; throw error }
  }
  const deadline = Date.now() + 2000
  while (Date.now() < deadline && (alive(descendantPid) || fs.existsSync(leasePath))) {
    await new Promise(resolve => setTimeout(resolve, 20))
  }
  if (alive(descendantPid)) {
    process.kill(descendantPid, 'SIGKILL')
    assert.fail('cancellation leaked the native compiler descendant')
  }
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing', 'cancellation releases the scheduling lease')
  assert.strictEqual(fs.existsSync(`${dynamicOutput}.hxhx-macro-host-input`), false, 'cancellation removes generated inputs')
  console.log('MACRO_HOST_HEAVY_RUN_LEASE_FIXTURE:PASS timeout=2 nested=1 direct=2 failure=2 queued=1 cancellation=1 stage3-stop=4')
} finally {
  if (peer && peer.status === 'acquired') releaseLease({ leasePath, ownerPid: process.pid, ownerToken: peer.record.owner.token })
  fs.rmSync(fixtureRoot, { recursive: true, force: true })
}

}
main().catch(error => { console.error(error); process.exitCode = 1 })
