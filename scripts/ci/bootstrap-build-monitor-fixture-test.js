#!/usr/bin/env node
'use strict'

// Exercise the real build wrapper without compiling the compiler. Long-lived
// timers must not retain its output pipe or survive a finished/failed build.
const assert = require('assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn, spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-build-monitors-'))
const fixture = path.join(temporary, 'repo')
const bin = path.join(temporary, 'bin')
const pids = path.join(temporary, 'pids')
const control = spawn('/bin/sleep', ['120'], { stdio: 'ignore' })

function active(pid) {
  const result = spawnSync('ps', ['-o', 'state=', '-p', String(pid)], { encoding: 'utf8' })
  return result.status === 0 && result.stdout.trim() !== '' && !result.stdout.trim().startsWith('Z')
}

function executable(name, text) {
  fs.writeFileSync(path.join(bin, name), text, { mode: 0o755 })
}

try {
  for (const directory of [bin, pids, path.join(fixture, 'scripts/hxhx'), path.join(fixture, 'packages/hxhx/bootstrap_out')]) {
    fs.mkdirSync(directory, { recursive: true })
  }
  for (const name of ['build-hxhx.sh', 'stage0-process-watchdog.sh']) {
    fs.copyFileSync(path.join(root, 'scripts/hxhx', name), path.join(fixture, 'scripts/hxhx', name))
  }
  assert.equal(spawnSync('git', ['init', '-q', fixture]).status, 0)
  fs.writeFileSync(path.join(fixture, 'packages/hxhx/bootstrap_out/dune'), '; fixture\n')
  executable('ocamlc', '#!/usr/bin/env bash\nexit 0\n')
  executable('sleep', `#!/usr/bin/env bash
printf '%s\\n' "$$" > "$MONITOR_PIDS/$$.pid"
exec /bin/sleep "$@"
`)
  executable('dune', `#!/usr/bin/env bash
set -euo pipefail
if [ "$MONITOR_CASE" = timeout ]; then
  sleep 60 &
  wait
  exit 0
fi
/bin/sleep 0.2
if [ "$MONITOR_CASE" = failure ]; then exit 7; fi
mkdir -p _build/default
touch "_build/default/$(basename "$2")"
`)

  for (const name of ['success', 'failure', 'timeout']) {
    const started = Date.now()
    const result = spawnSync('bash', ['-c', 'set -euo pipefail; artifact="$(bash "$1")"; printf "%s\\n" "$artifact"', 'fixture', path.join(fixture, 'scripts/hxhx/build-hxhx.sh')], {
      encoding: 'utf8',
      timeout: 15000,
      env: {
        ...process.env,
        PATH: bin + path.delimiter + process.env.PATH,
        MONITOR_CASE: name,
        MONITOR_PIDS: pids,
        HXHX_FORCE_STAGE0: '0',
        HXHX_FORBID_STAGE0: '1',
        HXHX_BOOTSTRAP_BUILD_DIR: path.join(temporary, 'build-' + name),
        HXHX_BOOTSTRAP_BUILD_PRUNE: '0',
        HXHX_BOOTSTRAP_PREFER_NATIVE: '0',
        HXHX_BOOTSTRAP_HEARTBEAT: '60',
        HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS: name === 'timeout' ? '1' : '60',
      },
    })
    assert.ifError(result.error)
    assert.equal(result.status, name === 'success' ? 0 : name === 'failure' ? 7 : 124, result.stderr)
    assert.ok(Date.now() - started < 15000, 'build waited for an unused timer')
    if (name === 'success') {
      assert.equal(result.stdout.trim(), path.join(temporary, 'build-success/_build/default/out.bc'))
      assert.ok(fs.existsSync(result.stdout.trim()))
    } else {
      assert.equal(result.stdout, '')
    }
    const observed = fs.readdirSync(pids)
    assert.ok(observed.length >= 2, 'fixture did not observe the monitor timers')
    for (const file of observed) {
      assert.ok(!active(Number(fs.readFileSync(path.join(pids, file), 'utf8'))), 'owned timer or build child survived: ' + file)
    }
    assert.ok(active(control.pid), 'cleanup stopped the unrelated control process')
    console.log('BOOTSTRAP_BUILD_MONITORS:PASS ' + name)
  }
} finally {
  for (const file of fs.existsSync(pids) ? fs.readdirSync(pids) : []) {
    try { process.kill(Number(fs.readFileSync(path.join(pids, file), 'utf8')), 'SIGTERM') } catch (_) {}
  }
  control.kill('SIGTERM')
  fs.rmSync(temporary, { recursive: true, force: true })
}
