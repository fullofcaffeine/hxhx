#!/usr/bin/env node
'use strict'

const fs = require('fs')
const path = require('path')
const { spawn } = require('child_process')

/**
 * Runs one local diagnostic command with a timeout, heartbeat, and log file.
 *
 * This is for ad hoc long-running probes where there is no repo-specific runner
 * with its own timeout. Prefer dedicated gate runners when they exist; use this
 * helper instead of shell alarm wrappers for one-off commands.
 */

function fail(message) {
  console.error(`[run-with-timeout-heartbeat] ERROR: ${message}`)
  process.exit(1)
}

function usage() {
  console.log(`Usage:
  node scripts/dev/run-with-timeout-heartbeat.js --timeout <sec> --heartbeat <sec> --log <path> -- <command> [args...]

Options:
  --timeout <sec>    0 disables timeout
  --heartbeat <sec>  0 disables heartbeat output
  --log <path>       required command stdout/stderr log
  --cwd <path>       command working directory, default current directory
  --label <name>     label used in heartbeat lines, default command basename`)
}

function parsePositiveInteger(name, value) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed < 0) fail(`${name} must be a non-negative integer, got ${value}`)
  return parsed
}

function parseArgs(argv) {
  const options = {
    timeout: null,
    heartbeat: 30,
    log: '',
    cwd: process.cwd(),
    label: '',
    command: []
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--help' || arg === '-h') {
      usage()
      process.exit(0)
    } else if (arg === '--timeout') {
      i += 1
      if (i >= argv.length) fail('--timeout requires seconds')
      options.timeout = parsePositiveInteger('--timeout', argv[i])
    } else if (arg === '--heartbeat') {
      i += 1
      if (i >= argv.length) fail('--heartbeat requires seconds')
      options.heartbeat = parsePositiveInteger('--heartbeat', argv[i])
    } else if (arg === '--log') {
      i += 1
      if (i >= argv.length) fail('--log requires a path')
      options.log = argv[i]
    } else if (arg === '--cwd') {
      i += 1
      if (i >= argv.length) fail('--cwd requires a path')
      options.cwd = argv[i]
    } else if (arg === '--label') {
      i += 1
      if (i >= argv.length) fail('--label requires a name')
      options.label = argv[i]
    } else if (arg === '--') {
      options.command = argv.slice(i + 1)
      break
    } else {
      fail(`unknown option before --: ${arg}`)
    }
  }
  if (options.timeout === null) fail('--timeout is required; use --timeout 0 to disable')
  if (!options.log) fail('--log is required')
  if (options.command.length === 0) fail('missing command after --')
  return options
}

function fileSize(file) {
  try {
    return fs.statSync(file).size
  } catch (_) {
    return 0
  }
}

function killChildGroup(child, signal) {
  try {
    if (process.platform === 'win32') {
      child.kill(signal)
    } else {
      process.kill(-child.pid, signal)
    }
  } catch (_) {
    try {
      child.kill(signal)
    } catch (_) {}
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2))
  const logPath = path.resolve(options.log)
  fs.mkdirSync(path.dirname(logPath), { recursive: true })
  const log = fs.createWriteStream(logPath, { flags: 'w' })
  const [command, ...args] = options.command
  const label = options.label || path.basename(command)
  const started = Date.now()
  let timedOut = false
  let closed = false
  let killTimer = null

  const child = spawn(command, args, {
    cwd: options.cwd,
    detached: process.platform !== 'win32',
    stdio: ['ignore', 'pipe', 'pipe']
  })

  child.stdout.pipe(log)
  child.stderr.pipe(log)

  console.log(`${label}_start pid=${child.pid} timeout=${options.timeout}s heartbeat=${options.heartbeat}s log=${logPath}`)

  const heartbeatTimer =
    options.heartbeat > 0
      ? setInterval(() => {
          const elapsed = Math.floor((Date.now() - started) / 1000)
          console.log(`${label}_heartbeat elapsed=${elapsed}s pid=${child.pid} log=${fileSize(logPath)}B`)
        }, options.heartbeat * 1000)
      : null

  const timeoutTimer =
    options.timeout > 0
      ? setTimeout(() => {
          timedOut = true
          console.error(`${label}_timeout elapsed=${options.timeout}s pid=${child.pid} log=${logPath}`)
          killChildGroup(child, 'SIGTERM')
          killTimer = setTimeout(() => {
            if (!closed) killChildGroup(child, 'SIGKILL')
          }, 5000)
        }, options.timeout * 1000)
      : null

  child.on('error', error => {
    if (heartbeatTimer) clearInterval(heartbeatTimer)
    if (timeoutTimer) clearTimeout(timeoutTimer)
    if (killTimer) clearTimeout(killTimer)
    log.end()
    fail(`${command} failed to start: ${error.message}`)
  })

  child.on('close', (code, signal) => {
    closed = true
    if (heartbeatTimer) clearInterval(heartbeatTimer)
    if (timeoutTimer) clearTimeout(timeoutTimer)
    if (killTimer) clearTimeout(killTimer)
    log.end()
    const elapsed = Math.floor((Date.now() - started) / 1000)
    const exitCode = timedOut ? 124 : code === null ? 1 : code
    const status = timedOut ? 'timeout' : exitCode === 0 ? 'ok' : 'error'
    console.log(`${label}_end status=${status} exit=${exitCode} signal=${signal || ''} elapsed=${elapsed}s log=${logPath}`)
    process.exit(exitCode)
  })
}

main()
