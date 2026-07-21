#!/usr/bin/env node
/**
 * Runs one unchanged local command while holding the Haxe-family heavy-run lease.
 *
 * The wrapper is scheduling only: it never changes the child command or its
 * correctness result. CI bypasses the user-scoped lease, while nested local
 * wrappers reuse the outer owner identity without releasing its lease.
 */

'use strict'

const path = require('path')
const { spawn } = require('child_process')
const {
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  acquireLease,
  defaultLeasePath,
  leaseSummary,
  releaseLease,
  touchLease
} = require('./local-heavy-run-lease.js')

const TEMPORARY_FAILURE_EXIT_CODE = 75
const SIGNAL_EXIT_CODES = new Map([
  ['SIGINT', 130],
  ['SIGTERM', 143],
  ['SIGHUP', 129]
])

function fail(message) {
  throw new Error(message)
}

function readValue(argv, index, flag) {
  if (index + 1 >= argv.length) fail(`${flag} requires a value`)
  return argv[index + 1]
}

function parseNumber(value, label, allowZero) {
  const parsed = Number(value)
  if (!Number.isFinite(parsed) || (allowZero ? parsed < 0 : parsed <= 0)) {
    fail(`${label} must be a ${allowZero ? 'non-negative' : 'positive'} number`)
  }
  return parsed
}

function parseArgs(argv, env = process.env) {
  const options = {
    command: [],
    help: false,
    label: 'heavy-local-run',
    leaseFile: defaultLeasePath(env),
    pollSeconds: env.HAXE_FAMILY_HEAVY_RUN_POLL_SECONDS || '2',
    repository: 'hxhx',
    waitSeconds: env.HAXE_FAMILY_HEAVY_RUN_WAIT_SECONDS || '0'
  }
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index]
    if (arg === '--') {
      options.command = argv.slice(index + 1)
      break
    }
    if (arg === '-h' || arg === '--help') {
      options.help = true
    } else if (arg === '--wait-seconds') {
      options.waitSeconds = readValue(argv, index, arg)
      index++
    } else if (arg === '--poll-seconds') {
      options.pollSeconds = readValue(argv, index, arg)
      index++
    } else if (arg === '--label') {
      options.label = readValue(argv, index, arg)
      index++
    } else if (arg === '--repository') {
      options.repository = readValue(argv, index, arg)
      index++
    } else if (arg === '--lease-file') {
      options.leaseFile = path.resolve(readValue(argv, index, arg))
      index++
    } else {
      fail(`unknown option: ${arg}`)
    }
  }
  options.waitSeconds = parseNumber(options.waitSeconds, '--wait-seconds', true)
  options.pollSeconds = parseNumber(options.pollSeconds, '--poll-seconds', false)
  if (!options.help && options.command.length === 0) fail('a command is required after --')
  return options
}

function usage() {
  console.log(`Usage: node scripts/hxhx/with-heavy-run-lease.js [options] -- command [args...]

Options:
  --wait-seconds <number>  Maximum local wait before exit 75
  --poll-seconds <number>  Lease resample interval (default: 2)
  --label <text>           Human-readable workload name
  --repository <text>      Repository identity stored in the lease
  --lease-file <path>      Override the shared user-scoped lease path
  -h, --help               Show this help

CI runs the command immediately. Nested Haxe-family wrappers reuse the outer
lease owner rather than deadlocking or releasing another wrapper's lease.`)
}

function isCiEnvironment(env = process.env) {
  const value = String(env.CI || '').trim().toLowerCase()
  return value !== '' && value !== '0' && value !== 'false' && value !== 'no'
}

function inheritedOwnerPid(env = process.env) {
  const raw = env.HAXE_FAMILY_HEAVY_RUN_LEASE_OWNER_PID || env.HXHX_HEAVY_RUN_LEASE_OWNER_PID || ''
  if (!raw) return 0
  const pid = Number(raw)
  if (!Number.isInteger(pid) || pid <= 0) fail('inherited heavy-run lease owner PID must be a positive integer')
  return pid
}

function delay(milliseconds, cancellation) {
  return new Promise(resolve => {
    const timer = setTimeout(() => {
      cancellation.wake = null
      resolve()
    }, milliseconds)
    cancellation.wake = () => {
      clearTimeout(timer)
      cancellation.wake = null
      resolve()
    }
  })
}

/**
 * Identifies changes that a waiting user needs to see.
 *
 * The heartbeat age changes on every poll even when the same command still owns
 * the lease. It remains available in `leaseSummary` for diagnostics, but is not
 * part of this signature so one quiet wait does not flood the terminal.
 */
function waitingStateSignature(summary) {
  return JSON.stringify({
    status: summary.status,
    reason: summary.reason,
    ownerPid: summary.ownerPid,
    ownerStartedAt: summary.ownerStartedAt,
    ownerLabel: summary.ownerLabel,
    ownerRepository: summary.ownerRepository
  })
}

async function waitForLease(options, ownerPid, cancellation) {
  const deadline = Date.now() + options.waitSeconds * 1000
  let lastSignature = ''
  while (!cancellation.signal) {
    const result = acquireLease({
      leasePath: options.leaseFile,
      ownerPid,
      label: options.label,
      repository: options.repository
    })
    if (result.status === 'acquired' || result.status === 'reentrant') return result
    if (result.status === 'incompatible') {
      const summary = leaseSummary(result)
      fail(`shared lease is incompatible (${summary.reason || 'unknown format'}); refusing to replace it`)
    }

    const summary = leaseSummary(result)
    const signature = waitingStateSignature(summary)
    if (signature !== lastSignature) {
      console.log(
        `HAXE_FAMILY_HEAVY_RUN:WAITING label=${JSON.stringify(options.label)} ` +
          `owner_pid=${summary.ownerPid || 'unknown'} owner=${JSON.stringify(summary.ownerLabel || 'unknown')} ` +
          `repository=${JSON.stringify(summary.ownerRepository || 'unknown')}`
      )
      lastSignature = signature
    }
    const remainingMs = deadline - Date.now()
    if (remainingMs <= 0) return { status: 'timed_out' }
    await delay(Math.min(options.pollSeconds * 1000, remainingMs), cancellation)
  }
  return { status: 'cancelled' }
}

function runCommand(command, env, cancellation) {
  return new Promise((resolve, reject) => {
    const child = spawn(command[0], command.slice(1), {
      cwd: process.cwd(),
      detached: process.platform !== 'win32',
      env,
      stdio: 'inherit'
    })
    cancellation.child = child
    child.once('error', reject)
    child.once('close', (code, signal) => {
      cancellation.child = null
      resolve({ code, signal })
    })
  })
}

function forwardSignal(child, signal) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return
  try {
    if (process.platform !== 'win32') process.kill(-child.pid, signal)
    else child.kill(signal)
  } catch (error) {
    if (!error || error.code !== 'ESRCH') throw error
  }
}

async function main(argv = process.argv.slice(2), env = process.env) {
  let heartbeat = null
  let options
  let ownedRecord = null
  const cancellation = { child: null, signal: '', wake: null }
  const onSignal = signal => {
    if (!cancellation.signal) cancellation.signal = signal
    if (cancellation.wake) cancellation.wake()
    forwardSignal(cancellation.child, signal)
  }
  for (const signal of SIGNAL_EXIT_CODES.keys()) process.on(signal, onSignal)

  try {
    options = parseArgs(argv, env)
    if (options.help) {
      usage()
      return 0
    }
    if (isCiEnvironment(env)) {
      console.log(`HAXE_FAMILY_HEAVY_RUN:CI_BYPASS label=${JSON.stringify(options.label)}`)
      const result = await runCommand(options.command, env, cancellation)
      return result.code === null ? SIGNAL_EXIT_CODES.get(result.signal) || 1 : result.code
    }

    const inheritedPid = inheritedOwnerPid(env)
    const ownerPid = inheritedPid || process.pid
    const lease = await waitForLease(options, ownerPid, cancellation)
    if (lease.status === 'cancelled') return SIGNAL_EXIT_CODES.get(cancellation.signal) || 1
    if (lease.status === 'timed_out') {
      console.error(
        `HAXE_FAMILY_HEAVY_RUN:TIMEOUT label=${JSON.stringify(options.label)} wait_seconds=${options.waitSeconds}`
      )
      return TEMPORARY_FAILURE_EXIT_CODE
    }

    if (lease.status === 'acquired') ownedRecord = lease.record
    if (ownedRecord) {
      heartbeat = setInterval(() => {
        if (!touchLease({ leasePath: options.leaseFile, ownerToken: ownedRecord.owner.token })) {
          console.error('HAXE_FAMILY_HEAVY_RUN:LEASE_LOST')
          onSignal('SIGTERM')
        }
      }, DEFAULT_HEARTBEAT_INTERVAL_MS)
      heartbeat.unref()
    }

    console.log(
      `HAXE_FAMILY_HEAVY_RUN:${lease.status.toUpperCase()} label=${JSON.stringify(options.label)} owner_pid=${ownerPid}`
    )
    const childEnv = {
      ...env,
      HAXE_FAMILY_HEAVY_RUN_LEASE_FILE: options.leaseFile,
      HAXE_FAMILY_HEAVY_RUN_LEASE_OWNER_PID: String(ownerPid),
      HXHX_HEAVY_RUN_LEASE_FILE: options.leaseFile,
      HXHX_HEAVY_RUN_LEASE_OWNER_PID: String(ownerPid)
    }
    const result = await runCommand(options.command, childEnv, cancellation)
    if (cancellation.signal) return SIGNAL_EXIT_CODES.get(cancellation.signal) || 1
    return result.code === null ? SIGNAL_EXIT_CODES.get(result.signal) || 1 : result.code
  } finally {
    if (heartbeat) clearInterval(heartbeat)
    if (ownedRecord && options) {
      const released = releaseLease({
        leasePath: options.leaseFile,
        ownerPid: ownedRecord.owner.pid,
        ownerToken: ownedRecord.owner.token
      })
      console.log(`HAXE_FAMILY_HEAVY_RUN:LEASE_${released.status.toUpperCase()}`)
    }
    for (const signal of SIGNAL_EXIT_CODES.keys()) process.removeListener(signal, onSignal)
  }
}

if (require.main === module) {
  void main()
    .then(code => {
      process.exitCode = code
    })
    .catch(error => {
      console.error(`with-heavy-run-lease: ${error.message}`)
      process.exitCode = 2
    })
}

module.exports = {
  TEMPORARY_FAILURE_EXIT_CODE,
  inheritedOwnerPid,
  isCiEnvironment,
  main,
  parseArgs,
  waitingStateSignature
}
