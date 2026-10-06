#!/usr/bin/env node
// Verify embedded runtime identity, warm-build invalidation, and source-free publication.
const assert = require('assert/strict')
const { spawn, spawnSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const net = require('net')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-managed-runtime-'))
const owner = path.join(temporary, 'owner')
const source = path.join(owner, 'src')
const launch = path.join(temporary, 'launch')
const headers = ['ManagedHeap.hpp', 'ManagedValue.hpp', 'ManagedMap.hpp', 'ManagedThrow.hpp', 'ManagedStack.hpp', 'ManagedCallable.hpp', 'ManagedOutput.hpp']
const haxe = process.env.HAXE || 'haxe'
const neko = process.env.NEKO || 'neko'
let server
let serverFailure = ''

function run(command, args, cwd = launch) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', timeout: 60000 })
  if (result.error) throw result.error
  assert.equal(result.status, 0, `${command} failed\n${result.stdout}${result.stderr}`)
  return result.stdout
}

function copy(relative, destination) {
  fs.mkdirSync(path.dirname(destination), { recursive: true })
  fs.copyFileSync(path.join(root, relative), destination)
}

function digest(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
}

async function availablePort() {
  const reservation = net.createServer()
  await new Promise((resolve, reject) => {
    reservation.once('error', reject)
    reservation.listen(0, '127.0.0.1', resolve)
  })
  const port = reservation.address().port
  await new Promise(resolve => reservation.close(resolve))
  return port
}

async function ready(port) {
  const deadline = Date.now() + 10000
  while (Date.now() < deadline) {
    if (server.exitCode !== null || serverFailure) throw new Error(`owned Haxe server failed: ${serverFailure}`)
    const connected = await new Promise(resolve => {
      const socket = net.connect({ host: '127.0.0.1', port })
      socket.setTimeout(100)
      socket.once('connect', () => { socket.end(); resolve(true) })
      socket.once('error', () => { socket.destroy(); resolve(false) })
      socket.once('timeout', () => { socket.destroy(); resolve(false) })
    })
    if (connected) return
    await new Promise(resolve => setTimeout(resolve, 25))
  }
  throw new Error('owned Haxe server did not listen within ten seconds')
}

async function stopServer() {
  if (!server || !server.pid || server.exitCode !== null || server.signalCode !== null) return
  await new Promise(resolve => {
    const force = setTimeout(() => server.kill('SIGKILL'), 2000)
    server.once('exit', () => { clearTimeout(force); resolve() })
    server.kill('SIGTERM')
  })
}

function observe(binary, directory, expected) {
  const records = JSON.parse(run(neko, [binary, directory]))
  assert.deepEqual(records, headers.map(name => ({ name, sha256: expected[name] })))
  for (const name of headers) assert.equal(digest(path.join(directory, name)), expected[name])
}

async function main() {
  try {
    fs.mkdirSync(launch, { recursive: true })
    for (const file of ['CppManagedRuntime.hx', 'CppManagedRuntimeMacro.hx']) {
      copy(`packages/hxhx-core/src/backend/cpp/${file}`, path.join(source, 'backend/cpp', file))
    }
    copy('packages/hxhx-core/src/backend/EmitArtifact.hx', path.join(source, 'backend/EmitArtifact.hx'))
    const initial = {}
    for (const name of headers) {
      const destination = path.join(owner, 'runtime/cpp', name)
      copy(`packages/hxhx-core/runtime/cpp/${name}`, destination)
      initial[name] = digest(destination)
    }
    fs.writeFileSync(path.join(source, 'RuntimeProbe.hx'), `
import backend.cpp.CppManagedRuntime;
class RuntimeProbe {
  static function main():Void {
    final runtime = new CppManagedRuntime();
    runtime.publish(Sys.args()[0]);
    Sys.println(haxe.Json.stringify([for (file in runtime.getFiles()) {name: file.name, sha256: file.sha256}]));
  }
}
`)
    const port = await availablePort()
    // Native Haxe and the project's Lix launcher both accept a bare port.
    // Readiness still connects only to loopback.
    server = spawn(haxe, ['--wait', String(port)], { cwd: launch, stdio: ['ignore', 'ignore', 'pipe'] })
    server.on('error', error => { serverFailure = error.message })
    server.stderr.on('data', chunk => { serverFailure = (serverFailure + chunk).slice(-8192) })
    await ready(port)
    const binary = path.join(launch, 'probe.n')
    const compile = ['--connect', String(port), '-cp', source, '-main', 'RuntimeProbe', '-neko', binary]
    run(haxe, compile)
    const originalBinary = path.join(launch, 'original.n')
    fs.copyFileSync(binary, originalBinary)
    observe(binary, path.join(launch, 'initial'), initial)

    const changed = path.join(owner, 'runtime/cpp/ManagedCallable.hpp')
    fs.appendFileSync(changed, '\n// Isolated fixture revision for warm compiler invalidation.\n')
    // Distinct timestamps also exercise hosts whose compiler uses coarse file times.
    const changedTime = new Date(Date.now() + 2000)
    fs.utimesSync(changed, changedTime, changedTime)
    const updated = { ...initial, 'ManagedCallable.hpp': digest(changed) }
    assert.notEqual(updated['ManagedCallable.hpp'], initial['ManagedCallable.hpp'])
    run(haxe, compile)
    observe(binary, path.join(launch, 'updated'), updated)
    await stopServer()

    fs.rmSync(owner, { recursive: true })
    observe(originalBinary, path.join(launch, 'relocated-original'), initial)
    observe(binary, path.join(launch, 'relocated-updated'), updated)
    console.log('CPP_MANAGED_RUNTIME_WARM_INVALIDATION:PASS')
    console.log('CPP_MANAGED_RUNTIME_RELOCATION:PASS')
  } finally {
    await stopServer()
    fs.rmSync(temporary, { recursive: true, force: true })
  }
}

main().catch(error => { console.error(error); process.exitCode = 1 })
