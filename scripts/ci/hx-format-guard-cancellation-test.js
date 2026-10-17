#!/usr/bin/env node
'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const crypto = require('node:crypto')
const { spawn, spawnSync } = require('node:child_process')
const delay = ms => new Promise(resolve => setTimeout(resolve, ms))

function alive(pid) {
  try { process.kill(pid, 0); return true } catch (error) {
    if (error.code === 'ESRCH') return false
    throw error
  }
}

async function waitFor(predicate, description) {
  const deadline = Date.now() + 5000
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error('timed out waiting for ' + description)
    await delay(20)
  }
}

/** Observe two live formatter groups, interrupt their guard, and verify ownership. */
async function check(signal, phase) {
  const started = Date.now()
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-format-guard-cancel-'))
  const records = path.join(root, 'workers.jsonl')
  const pids = () => fs.existsSync(records) ? fs.readFileSync(records, 'utf8').trim().split('\n').filter(Boolean).flatMap(JSON.parse) : []
  let child
  let output = ''
  const unrelated = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' })
  try {
    assert.equal(spawnSync('git', ['init', '-q', root]).status, 0)
    const scripts = path.join(root, 'scripts/lint')
    fs.mkdirSync(scripts, { recursive: true })
    for (const file of ['hx-format-guard.js', 'formatter-toolchain.js']) {
      fs.copyFileSync(path.resolve(__dirname, '../lint', file), path.join(scripts, file))
    }
    for (let index = 0; index < 5; index++) fs.writeFileSync(path.join(root, `File${index}.hx`), `class File${index} {}\n`)
    if (phase === 'sentinel') {
      const sentinel = path.join(root, 'packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx')
      fs.mkdirSync(path.dirname(sentinel), { recursive: true })
      fs.writeFileSync(sentinel, 'class OcamlBuilder {}\n')
    }
    assert.equal(spawnSync('git', ['add', '*.hx'], { cwd: root }).status, 0)
    const source = `
const fs = require('node:fs')
const { spawn } = require('node:child_process')
if (process.argv.includes('--help') && process.env.FORMAT_PHASE !== 'help') process.exit(0)
if (process.argv.includes('--check') && process.env.FORMAT_PHASE === 'sentinel') process.exit(0)
const worker = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' })
fs.appendFileSync(process.env.FORMAT_WORKERS, JSON.stringify([process.pid, worker.pid]) + '\\n')
setInterval(() => {}, 1000)
`
    const artifactSha256 = crypto.createHash('sha256').update(source).digest('hex')
    fs.writeFileSync(path.join(scripts, 'formatter-toolchain.lock.json'), JSON.stringify({ artifactSha256 }))
    const artifact = path.join(root, '.tmp/formatter-toolchain', artifactSha256, 'run.js')
    fs.mkdirSync(path.dirname(artifact), { recursive: true })
    fs.writeFileSync(artifact, source)
    child = spawn(process.execPath, [path.join(scripts, 'hx-format-guard.js')], {
      cwd: root, detached: true,
      env: { ...process.env, FORMAT_WORKERS: records, FORMAT_PHASE: phase, HX_FORMAT_JOBS: '2', HX_FORMAT_OVERSIZED_JOBS: '2', HX_FORMAT_TIMEOUT_SECONDS: '30' },
      stdio: ['ignore', 'pipe', 'pipe']
    })
    let result
    child.stdout.on('data', chunk => { output += chunk })
    child.stderr.on('data', chunk => { output += chunk })
    child.on('close', (code, exitSignal) => { result = { code, signal: exitSignal } })
    const expectedPids = phase === 'workers' ? 4 : 2
    await waitFor(() => pids().length === expectedPids, 'formatter groups for ' + phase)
    assert.ok(pids().every(alive), 'the formatter and descendant PIDs must be live before interruption')
    child.kill(signal)
    await waitFor(() => result !== undefined, 'guard exit')
    await waitFor(() => pids().every(pid => !alive(pid)), 'all owned formatter processes to exit')
    assert.equal(result.code, signal === 'SIGINT' ? 130 : 143, output)
    assert.equal(result.signal, null)
    assert.equal(pids().length, expectedPids, 'later tasks must not start after cancellation')
    assert.ok(alive(unrelated.pid), 'the guard must leave caller-owned processes alone')
    console.log(`HX_FORMAT_GUARD_PHASE:PASS phase=${phase} signal=${signal} elapsedMs=${Date.now() - started}`)
  } catch (error) {
    error.message += '\nGuard output:\n' + output
    throw error
  } finally {
    // These exact PIDs were created and recorded by this fixture, including on failure.
    for (const pid of pids().reverse()) {
      try { process.kill(pid, 'SIGKILL') } catch (error) { if (error.code !== 'ESRCH') throw error }
    }
    if (child && child.exitCode === null && child.signalCode === null) child.kill('SIGKILL')
    unrelated.kill('SIGKILL')
    await waitFor(() => pids().every(pid => !alive(pid)) && !alive(unrelated.pid), 'fixture cleanup')
    fs.rmSync(root, { recursive: true, force: true })
  }
}

async function main() {
  if (process.platform === 'win32') {
    console.log('HX_FORMAT_GUARD_CANCELLATION:SKIP POSIX process groups')
    return
  }
  for (const phase of ['help', 'workers', 'sentinel']) {
    await check('SIGTERM', phase)
    await check('SIGINT', phase)
  }
  console.log('HX_FORMAT_GUARD_CANCELLATION:PASS')
}

main().catch(error => { console.error(error); process.exitCode = 1 })
