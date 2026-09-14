#!/usr/bin/env node
'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawn, spawnSync } = require('node:child_process')
const { runCommandWithTimeout } = require('../lint/hx-format-guard.js')

/** Prove CLI output, process ownership, and optional real formatter parity. */
const wrapper = path.resolve(__dirname, '../lint/hx-format-changed.js')
const delay = ms => new Promise(resolve => setTimeout(resolve, ms))

/** Compare real formatting bytes and check diagnostics on identical inputs. */
async function checkOfficialFormatter() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-format-parity-'))
  try {
    assert.equal(spawnSync('git', ['init', '-q', root]).status, 0)
    fs.copyFileSync(path.resolve(__dirname, '../../hxformat.json'), path.join(root, 'hxformat.json'))
    const file = path.join(root, 'Example.hx')
    const original = 'class Example{static function main(){var message="café";trace(message);}}\n'
    const normalize = text => text.replace(/((?:Checked|Formatted) \d+(?:\/\d+)? files in )\d+(?:\.\d+)? s\./g, '$1<time> s.')
    const wrapperErrors = text => text.split('\n').filter(line => !line.startsWith('[hx-format-changed]')).join('\n')
    const run = async (wrapped, check) => {
      const args = wrapped ? [wrapper, check ? '--check' : '--write', file]
        : ['run', 'formatter', '-s', file, ...(check ? ['--check'] : [])]
      const result = await runCommandWithTimeout(wrapped ? process.execPath : 'haxelib', args, { cwd: root, timeoutMs: 15000 })
      assert.equal(result.timedOut, false, 'real formatter fixture must finish within its deadline')
      assert.equal(result.error, undefined, 'the official formatter must be installed')
      return result
    }
    fs.writeFileSync(file, original)
    const directFailure = await run(false, true)
    const wrappedFailure = await run(true, true)
    assert.notEqual(directFailure.code, 0, 'the input must need formatting')
    assert.equal(wrappedFailure.code, directFailure.code)
    assert.equal(normalize(wrappedFailure.stdout), normalize(directFailure.stdout))
    assert.equal(wrapperErrors(wrappedFailure.stderr), directFailure.stderr)
    assert.equal(fs.readFileSync(file, 'utf8'), original, 'checks must not modify source')
    assert.equal((await run(false, false)).code, 0)
    const expected = fs.readFileSync(file)
    assert.notDeepEqual(expected, Buffer.from(original))
    fs.writeFileSync(file, original)
    assert.equal((await run(true, false)).code, 0)
    assert.deepEqual(fs.readFileSync(file), expected, 'formatted bytes must match the official formatter')
    const directSuccess = await run(false, true)
    const wrappedSuccess = await run(true, true)
    assert.equal(directSuccess.code, 0)
    assert.equal(wrappedSuccess.code, 0)
    assert.equal(normalize(wrappedSuccess.stdout), normalize(directSuccess.stdout))
    assert.equal(wrapperErrors(wrappedSuccess.stderr), directSuccess.stderr)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

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

/** Run the real CLI against a formatter with observable output and descendants. */
async function checkCase(mode, signal) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-format-changed-'))
  let child
  const ownedPids = []
  try {
    assert.equal(spawnSync('git', ['init', '-q', root]).status, 0)
    const bin = path.join(root, 'bin')
    fs.mkdirSync(bin)
    fs.writeFileSync(path.join(root, 'Example.hx'), 'class Example {}\n')
    fs.writeFileSync(path.join(bin, 'haxelib'), `#!/usr/bin/env node
const fs = require('node:fs')
const { spawn } = require('node:child_process')
fs.appendFileSync(process.env.FORMAT_CALLS, JSON.stringify(process.argv.slice(2)) + '\\n')
if (process.argv.includes('--help')) process.exit(0)
if (process.env.FORMAT_MODE === 'exit') {
  const output = Buffer.from('formatter stdout café\\n')
  process.stdout.write(output.subarray(0, output.length - 2))
  setTimeout(() => process.stdout.write(output.subarray(output.length - 2)), 20)
  process.stderr.write('formatter stderr\\n')
  process.exitCode = 23
} else {
  const worker = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'inherit' })
  fs.writeFileSync(process.env.FORMAT_PIDS, JSON.stringify([process.pid, worker.pid]))
  process.stdout.write('formatter ready\\n')
  const timer = setInterval(() => {
    if (fs.existsSync(process.env.FORMAT_RELEASE)) {
      clearInterval(timer)
      worker.once('exit', () => { process.stdout.write('formatter done\\n') })
      worker.kill('SIGTERM')
    }
  }, 20)
}
`, { mode: 0o755 })
    const calls = path.join(root, 'calls.jsonl')
    const pidFile = path.join(root, 'pids.json')
    const release = path.join(root, 'release')
    child = spawn(process.execPath, [wrapper, '--check', 'Example.hx'], {
      cwd: root,
      detached: process.platform !== 'win32',
      env: {
        ...process.env,
        PATH: bin + path.delimiter + process.env.PATH,
        FORMAT_CALLS: calls,
        FORMAT_PIDS: pidFile,
        FORMAT_RELEASE: release,
        FORMAT_MODE: mode,
        HX_FORMAT_TIMEOUT_SECONDS: mode === 'timeout' ? '1' : '10'
      },
      stdio: ['ignore', 'pipe', 'pipe']
    })
    let stdout = ''
    let stderr = ''
    let result
    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', text => { stdout += text })
    child.stderr.on('data', text => { stderr += text })
    child.on('close', (code, exitSignal) => { result = { code, signal: exitSignal } })

    if (mode !== 'exit') {
      await waitFor(() => stdout.includes('formatter ready\n'), 'streamed output before formatter completion')
      ownedPids.push(...JSON.parse(fs.readFileSync(pidFile, 'utf8')))
      assert.ok(ownedPids.every(alive), 'the observed formatter tree must actually be live')
      if (signal) child.kill(signal)
      if (mode === 'release') {
        await delay(150)
        assert.equal(result, undefined, 'an observation delay must not end or restart the formatter')
        fs.writeFileSync(release, '')
      }
    }
    await waitFor(() => result !== undefined, 'wrapper exit')
    const expected = mode === 'exit' ? 23 : mode === 'timeout' ? 124 : signal === 'SIGINT' ? 130 : signal === 'SIGTERM' ? 143 : 0
    assert.equal(result.code, expected, 'the wrapper must preserve the formatter or cancellation exit status')
    assert.equal(result.signal, null)
    if (mode === 'exit') {
      assert.equal(stdout, 'formatter stdout café\n', 'stdout must preserve split UTF-8 characters without wrapper text')
      assert.ok(stderr.includes('formatter stderr\n'), 'formatter stderr must stay on stderr')
    }
    if (mode === 'release') assert.equal(stdout, 'formatter ready\nformatter done\n')
    await waitFor(() => ownedPids.every(pid => !alive(pid)), 'all formatter descendants to exit')
    assert.equal(fs.readFileSync(calls, 'utf8').trim().split('\n').length, 1,
      'one invocation must start one formatter, without help startup or retry')
  } finally {
    // Cleanup also owns deliberately failing runs against the old implementation.
    for (const pid of ownedPids.reverse()) {
      try { process.kill(pid, 'SIGKILL') } catch (error) { if (error.code !== 'ESRCH') throw error }
    }
    if (child && child.exitCode === null && child.signalCode === null) {
      try { process.kill(-child.pid, 'SIGKILL') } catch (error) { if (error.code !== 'ESRCH') throw error }
    }
    fs.rmSync(root, { recursive: true, force: true })
  }
}

async function main() {
  if (process.platform === 'win32') {
    console.log('HX_FORMAT_CHANGED_FIXTURE:SKIP POSIX executable fixture')
    return
  }
  await checkCase('exit')
  await checkCase('release')
  await checkCase('timeout')
  await checkCase('signal', 'SIGTERM')
  await checkCase('signal', 'SIGINT')
  if (process.argv.includes('--real-formatter')) await checkOfficialFormatter()
  console.log('HX_FORMAT_CHANGED_FIXTURE:PASS')
}

main().catch(error => { console.error(error); process.exitCode = 1 })
