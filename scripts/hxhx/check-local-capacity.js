#!/usr/bin/env node
/**
 * Refuse or annotate a heavyweight local compiler run when the host is already
 * saturated.
 *
 * This preflight is deliberately separate from compiler correctness. It reads
 * host load and reports other compiler processes before an expensive command
 * starts. Local `auto` policy stops with EX_TEMPFAIL when load is extreme;
 * shared CI only warns because runner scheduling is owned by the CI platform.
 */

'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync, spawn } = require('child_process')
const { CapacityQueueCancelledError, waitForCapacity } = require('./local-capacity-queue.js')
const {
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  acquireLease,
  defaultLeasePath,
  leaseSummary,
  releaseLease,
} = require('./local-heavy-run-lease.js')

const DEFAULT_MAX_LOAD_PER_CPU = 1.5
const MIN_COMPETING_CPU_PERCENT = 0.1
const BLOCKED_EXIT_CODE = 75
const CANCELLED_EXIT_CODE = 130
const VALID_POLICIES = new Set(['auto', 'require', 'warn', 'off'])

function usage() {
  console.log(`Usage: node scripts/hxhx/check-local-capacity.js [options]

Options:
  --policy <auto|require|warn|off>  Local auto=stop, CI auto=warn (default: auto)
  --label <text>                    Human-readable command/workload label
  --max-load-per-cpu <number>       Sustained normalized load limit (default: 1.5)
  --wait-seconds <number>           Wait this long for local capacity (default: 0)
  --poll-seconds <number>           Capacity resample interval (default: 10)
  --lease-owner-pid <pid>           Share the local heavy-run lease while waiting
  --lease-file <path>               Override the user-scoped shared lease path
  --release-lease                   Release a lease owned by --lease-owner-pid
  --json-out <path>                 Write the complete preflight report atomically
  --fixture <path>                  Read deterministic host state for fixture tests
  -h, --help                        Show this help

Environment equivalents:
  HXHX_HEAVY_RUN_CAPACITY_POLICY
  HXHX_HEAVY_RUN_MAX_LOAD_PER_CPU
  HXHX_HEAVY_RUN_WAIT_SECONDS
  HXHX_HEAVY_RUN_POLL_SECONDS
  HXHX_HEAVY_RUN_LEASE_FILE
  HXHX_HEAVY_RUN_CAPACITY_REPORT`)
}

function fail(message) {
  throw new Error(message)
}

function readValue(argv, index, flag) {
  if (index + 1 >= argv.length) fail(`${flag} requires a value`)
  return argv[index + 1]
}

function parseArgs(argv, env = process.env) {
  const options = {
    policy: env.HXHX_HEAVY_RUN_CAPACITY_POLICY || 'auto',
    label: 'heavy-local-run',
    maxLoadPerCpu: env.HXHX_HEAVY_RUN_MAX_LOAD_PER_CPU || String(DEFAULT_MAX_LOAD_PER_CPU),
    waitSeconds: env.HXHX_HEAVY_RUN_WAIT_SECONDS || '0',
    pollSeconds: env.HXHX_HEAVY_RUN_POLL_SECONDS || '10',
    leaseOwnerPid: '',
    leaseFile: defaultLeasePath(env),
    releaseLease: false,
    jsonOut: env.HXHX_HEAVY_RUN_CAPACITY_REPORT || '',
    fixture: '',
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '-h' || arg === '--help') {
      options.help = true
      continue
    }
    if (arg === '--policy') {
      options.policy = readValue(argv, i, arg)
      i += 1
      continue
    }
    if (arg === '--label') {
      options.label = readValue(argv, i, arg)
      i += 1
      continue
    }
    if (arg === '--max-load-per-cpu') {
      options.maxLoadPerCpu = readValue(argv, i, arg)
      i += 1
      continue
    }
    if (arg === '--wait-seconds') {
      options.waitSeconds = readValue(argv, i, arg)
      i += 1
      continue
    }
    if (arg === '--poll-seconds') {
      options.pollSeconds = readValue(argv, i, arg)
      i += 1
      continue
    }
    if (arg === '--lease-owner-pid') {
      options.leaseOwnerPid = readValue(argv, i, arg)
      i += 1
      continue
    }
    if (arg === '--lease-file') {
      options.leaseFile = path.resolve(readValue(argv, i, arg))
      i += 1
      continue
    }
    if (arg === '--release-lease') {
      options.releaseLease = true
      continue
    }
    if (arg === '--json-out') {
      options.jsonOut = readValue(argv, i, arg)
      i += 1
      continue
    }
    if (arg === '--fixture') {
      options.fixture = readValue(argv, i, arg)
      i += 1
      continue
    }
    fail(`unknown option: ${arg}`)
  }

  if (!VALID_POLICIES.has(options.policy)) {
    fail(`invalid policy ${options.policy}; expected auto, require, warn, or off`)
  }
  options.maxLoadPerCpu = Number(options.maxLoadPerCpu)
  if (!Number.isFinite(options.maxLoadPerCpu) || options.maxLoadPerCpu <= 0) {
    fail(`max load per CPU must be a positive number, received ${options.maxLoadPerCpu}`)
  }
  options.waitSeconds = Number(options.waitSeconds)
  if (!Number.isFinite(options.waitSeconds) || options.waitSeconds < 0) {
    fail(`wait seconds must be a non-negative number, received ${options.waitSeconds}`)
  }
  options.pollSeconds = Number(options.pollSeconds)
  if (!Number.isFinite(options.pollSeconds) || options.pollSeconds <= 0) {
    fail(`poll seconds must be a positive number, received ${options.pollSeconds}`)
  }
  if (options.leaseOwnerPid !== '') {
    options.leaseOwnerPid = Number(options.leaseOwnerPid)
    if (!Number.isInteger(options.leaseOwnerPid) || options.leaseOwnerPid <= 0) {
      fail(`lease owner PID must be a positive integer, received ${options.leaseOwnerPid}`)
    }
  } else {
    options.leaseOwnerPid = 0
  }
  if (options.releaseLease && options.leaseOwnerPid === 0) {
    fail('--release-lease requires --lease-owner-pid')
  }
  return options
}

function isCiEnvironment(env = process.env) {
  for (const name of ['CI', 'GITHUB_ACTIONS', 'BUILDKITE', 'CIRCLECI']) {
    const value = String(env[name] || '').toLowerCase()
    if (value && !['0', 'false', 'no', 'off'].includes(value)) return true
  }
  return false
}

function resolvePolicy(requestedPolicy, ci) {
  if (requestedPolicy !== 'auto') return requestedPolicy
  return ci ? 'warn' : 'require'
}

function classifyCompilerCommand(command) {
  const executable = String(command || '').trim().split(/\s+/, 1)[0]
  const basename = path.basename(executable).toLowerCase()
  if (/^hxhx(?:\.exe|\.bc)?$/.test(basename)) return 'hxhx'
  if (/^haxe(?:\.exe)?$/.test(basename)) return 'haxe'
  if (/^dune(?:\.exe)?$/.test(basename)) return 'dune'
  if (/^ocamlopt(?:\.opt|\.exe)?$/.test(basename)) return 'ocamlopt'
  if (/^ocamlc(?:\.opt|\.exe)?$/.test(basename)) return 'ocamlc'
  if (/^ocamlrun(?:\.exe)?$/.test(basename)) return 'ocamlrun'
  if (/^clang\+\+(?:\.exe)?$/.test(basename)) return 'clang++'
  if (/^g\+\+(?:\.exe)?$/.test(basename)) return 'g++'
  if (/^hxcpp(?:\.exe)?$/.test(basename) || /\/hxcpp\/|BuildTool/i.test(command)) return 'hxcpp'
  return ''
}

function parseProcessTable(text, currentPid = process.pid, parentPid = process.ppid) {
  const rows = []
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line) continue
    const match = line.match(/^(\d+)\s+(\d+)\s+([0-9.]+)\s+(\S+)\s+([\s\S]+)$/)
    if (!match) continue
    const pid = Number(match[1])
    if (pid === currentPid || pid === parentPid) continue
    const cpuPercent = Number(match[3])
    if (cpuPercent < MIN_COMPETING_CPU_PERCENT) continue
    const kind = classifyCompilerCommand(match[5])
    if (!kind) continue
    rows.push({
      pid,
      parentPid: Number(match[2]),
      cpuPercent,
      elapsed: match[4],
      kind,
    })
  }
  rows.sort((left, right) => right.cpuPercent - left.cpuPercent || left.pid - right.pid)
  return rows
}

function collectCompilerProcesses() {
  try {
    const output = execFileSync('ps', ['-axo', 'pid=,ppid=,%cpu=,etime=,command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    return { processes: parseProcessTable(output), error: '' }
  } catch (error) {
    return { processes: [], error: `ps collection failed: ${error.message}` }
  }
}

function normalizeFixtureProcess(row) {
  const command = String(row.command || '')
  const kind = String(row.kind || classifyCompilerCommand(command))
  if (!kind) return null
  return {
    pid: Number(row.pid || 0),
    parentPid: Number(row.parentPid || 0),
    cpuPercent: Number(row.cpuPercent || 0),
    elapsed: String(row.elapsed || 'unknown'),
    kind,
  }
}

function normalizeFixtureState(fixture) {
  return {
    source: 'fixture',
    timestamp: fixture.timestamp || '2000-01-01T00:00:00.000Z',
    cpuCount: Number(fixture.cpuCount),
    loadavg: fixture.loadavg.map(Number),
    totalMemoryBytes: Number(fixture.totalMemoryBytes || 0),
    freeMemoryBytes: Number(fixture.freeMemoryBytes || 0),
    ci: Boolean(fixture.ci),
    competitors: (fixture.processes || [])
      .map(normalizeFixtureProcess)
      .filter(row => row && row.cpuPercent >= MIN_COMPETING_CPU_PERCENT),
    collectionErrors: fixture.collectionErrors || [],
  }
}

function readLiveHostState() {
  const processCollection = collectCompilerProcesses()
  return {
    source: 'host',
    timestamp: new Date().toISOString(),
    cpuCount: typeof os.availableParallelism === 'function' ? os.availableParallelism() : os.cpus().length,
    loadavg: os.loadavg(),
    totalMemoryBytes: os.totalmem(),
    freeMemoryBytes: os.freemem(),
    ci: isCiEnvironment(),
    competitors: processCollection.processes,
    collectionErrors: processCollection.error ? [processCollection.error] : [],
  }
}

function createHostStateReader(options) {
  if (!options.fixture) return readLiveHostState
  const fixture = JSON.parse(fs.readFileSync(options.fixture, 'utf8'))
  const samples = Array.isArray(fixture.samples) && fixture.samples.length > 0 ? fixture.samples : [fixture]
  let sampleIndex = 0
  return () => {
    const sample = samples[Math.min(sampleIndex, samples.length - 1)]
    sampleIndex += 1
    return normalizeFixtureState({ ...fixture, ...sample, samples: undefined })
  }
}

function rounded(value) {
  return Math.round(value * 1000) / 1000
}

function evaluateCapacity(state, options) {
  if (!Number.isFinite(state.cpuCount) || state.cpuCount < 1) fail('host state must provide cpuCount >= 1')
  if (!Array.isArray(state.loadavg) || state.loadavg.length < 3 || state.loadavg.some(value => !Number.isFinite(value))) {
    fail('host state must provide three numeric load averages')
  }

  const normalized = state.loadavg.slice(0, 3).map(value => value / state.cpuCount)
  const sustainedLoadPerCpu = Math.min(normalized[0], normalized[1])
  const spikeLimit = options.maxLoadPerCpu * 1.5
  const observations = []
  if (sustainedLoadPerCpu >= options.maxLoadPerCpu) {
    observations.push('sustained_load')
  }
  if (normalized[0] >= spikeLimit) {
    observations.push('load_spike')
  }

  const requestedPolicy = options.policy
  const resolvedPolicy = resolvePolicy(requestedPolicy, state.ci)
  const overloaded = observations.length > 0
  let status = 'pass'
  let exitCode = 0
  if (resolvedPolicy === 'off') {
    status = 'off'
  } else if (overloaded && resolvedPolicy === 'warn') {
    status = 'warning'
  } else if (overloaded) {
    status = 'blocked'
    exitCode = BLOCKED_EXIT_CODE
  }

  return {
    schema: 'hxhx.local-capacity-preflight.v1',
    label: options.label,
    timestamp: state.timestamp,
    source: state.source,
    requestedPolicy,
    resolvedPolicy,
    status,
    exitCode,
    observations,
    thresholds: {
      maxSustainedLoadPerCpu: options.maxLoadPerCpu,
      maxSpikeLoadPerCpu: spikeLimit,
    },
    host: {
      ci: state.ci,
      cpuCount: state.cpuCount,
      load1: rounded(state.loadavg[0]),
      load5: rounded(state.loadavg[1]),
      load15: rounded(state.loadavg[2]),
      load1PerCpu: rounded(normalized[0]),
      load5PerCpu: rounded(normalized[1]),
      load15PerCpu: rounded(normalized[2]),
      sustainedLoadPerCpu: rounded(sustainedLoadPerCpu),
      totalMemoryBytes: state.totalMemoryBytes,
      freeMemoryBytes: state.freeMemoryBytes,
    },
    competingCompilerProcessCount: state.competitors.length,
    competingCompilerProcesses: state.competitors.slice(0, 12),
    collectionErrors: state.collectionErrors,
  }
}

function writeJsonAtomic(outputPath, report) {
  const absolute = path.resolve(outputPath)
  fs.mkdirSync(path.dirname(absolute), { recursive: true })
  const temporary = `${absolute}.tmp-${process.pid}`
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(report, null, 2)}\n`)
    fs.renameSync(temporary, absolute)
  } finally {
    if (fs.existsSync(temporary)) fs.rmSync(temporary, { force: true })
  }
  return absolute
}

function printReport(report, jsonOut) {
  const marker = report.status.toUpperCase()
  console.log(
    `HXHX_LOCAL_CAPACITY:${marker} label=${JSON.stringify(report.label)} policy=${report.resolvedPolicy} ` +
      `cpus=${report.host.cpuCount} load1=${report.host.load1} load5=${report.host.load5} ` +
      `load1_per_cpu=${report.host.load1PerCpu} sustained_per_cpu=${report.host.sustainedLoadPerCpu} ` +
      `competitors=${report.competingCompilerProcessCount} queue=${report.queue.outcome} ` +
      `wait_ms=${report.queue.waitedMs}`
  )

  if (report.status === 'warning' || report.status === 'blocked') {
    const action =
      report.status === 'blocked' && report.queue.outcome === 'timed_out'
        ? `timed out after ${report.queue.waitedMs}ms before expensive setup`
        : report.status === 'blocked'
          ? 'stopped before expensive setup'
          : 'continuing with a warning'
    console.error(
      `Heavy-run capacity ${action}: observations=${report.observations.join(',')} ` +
        `limit=${report.thresholds.maxSustainedLoadPerCpu} load-per-CPU.`
    )
    for (const row of report.competingCompilerProcesses.slice(0, 8)) {
      console.error(
        `  competing_compiler kind=${row.kind} pid=${row.pid} cpu=${row.cpuPercent}% elapsed=${row.elapsed}`
      )
    }
    if (report.status === 'blocked') {
      console.error(
        'Retry when the host is quieter. To accept the slowdown deliberately, set ' +
          'HXHX_HEAVY_RUN_CAPACITY_POLICY=off; this does not change compiler gate semantics.'
      )
    }
  }
  if (jsonOut) console.log(`hxhx_capacity_report=${jsonOut}`)
}

function printWaitingTransition({ report, waitedMs }) {
  console.log(
    `HXHX_LOCAL_CAPACITY:WAITING label=${JSON.stringify(report.label)} ` +
      `observations=${report.observations.join(',')} waited_ms=${waitedMs} ` +
      `competitors=${report.competingCompilerProcessCount}` +
      (report.lease && report.lease.ownerPid
        ? ` lease_owner_pid=${report.lease.ownerPid} lease_owner=${JSON.stringify(report.lease.ownerLabel)}`
        : '')
  )
}

function startLeaseWatchdog(options, leaseRecord) {
  const watcher = path.join(__dirname, 'local-heavy-run-lease-watch.js')
  const requestedInterval = Number(process.env.HXHX_HEAVY_RUN_LEASE_HEARTBEAT_MS || 0)
  const heartbeatIntervalMs =
    Number.isFinite(requestedInterval) && requestedInterval > 0
      ? requestedInterval
      : DEFAULT_HEARTBEAT_INTERVAL_MS
  const child = spawn(process.execPath, [watcher], {
    detached: true,
    stdio: 'ignore',
    env: {
      ...process.env,
      HXHX_HEAVY_RUN_WATCH_LEASE_FILE: options.leaseFile,
      HXHX_HEAVY_RUN_WATCH_OWNER_PID: String(leaseRecord.owner.pid),
      HXHX_HEAVY_RUN_WATCH_OWNER_STARTED_AT: leaseRecord.owner.startedAt,
      HXHX_HEAVY_RUN_WATCH_OWNER_TOKEN: leaseRecord.owner.token,
      HXHX_HEAVY_RUN_WATCH_INTERVAL_MS: String(heartbeatIntervalMs),
    },
  })
  child.unref()
}

function repositoryIdentity() {
  return path.basename(path.resolve(__dirname, '../..'))
}

function releaseOwnedLease(options) {
  const released = releaseLease({
    leasePath: options.leaseFile,
    ownerPid: options.leaseOwnerPid,
  })
  console.log(`HXHX_LOCAL_CAPACITY:LEASE_${released.status.toUpperCase()}`)
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2))
    if (options.help) {
      usage()
      return
    }
    if (options.releaseLease) {
      releaseOwnedLease(options)
      return
    }

    let acquiredLease = null
    const leaseEnabled = options.waitSeconds > 0 && options.leaseOwnerPid > 0
    const readHostState = createHostStateReader(options)
    const queued = await waitForCapacity({
      readReport: () => {
        const state = readHostState(options)
        const report = evaluateCapacity(state, options)
        if (
          !leaseEnabled ||
          state.ci ||
          report.resolvedPolicy !== 'require' ||
          report.status !== 'pass'
        ) {
          return report
        }

        const lease = acquireLease({
          leasePath: options.leaseFile,
          ownerPid: options.leaseOwnerPid,
          label: options.label,
          repository: repositoryIdentity(),
        })
        const summary = leaseSummary(lease)
        if (lease.status === 'acquired' || lease.status === 'reentrant') {
          acquiredLease = lease.status === 'acquired' ? lease.record : null
          return { ...report, lease: summary }
        }
        return {
          ...report,
          status: 'blocked',
          exitCode: BLOCKED_EXIT_CODE,
          observations: ['cooperative_lease'],
          lease: summary,
        }
      },
      maxWaitMs: options.waitSeconds * 1000,
      pollIntervalMs: options.pollSeconds * 1000,
      onWaiting: printWaitingTransition,
    })
    if (acquiredLease) startLeaseWatchdog(options, acquiredLease)
    const report = {
      ...queued.report,
      queue: {
        enabled: options.waitSeconds > 0,
        outcome: queued.outcome,
        waitedMs: queued.waitedMs,
        samples: queued.samples,
      },
      lease: queued.report.lease || { enabled: leaseEnabled, status: leaseEnabled ? 'not_acquired' : 'off' },
    }
    const jsonOut = options.jsonOut ? writeJsonAtomic(options.jsonOut, report) : ''
    printReport(report, jsonOut)
    process.exitCode = report.exitCode
  } catch (error) {
    if (error instanceof CapacityQueueCancelledError) {
      console.error('check-local-capacity: capacity wait cancelled')
      process.exitCode = CANCELLED_EXIT_CODE
      return
    }
    console.error(`check-local-capacity: ${error.message}`)
    process.exitCode = 2
  }
}

if (require.main === module) void main()

module.exports = {
  BLOCKED_EXIT_CODE,
  CANCELLED_EXIT_CODE,
  classifyCompilerCommand,
  evaluateCapacity,
  isCiEnvironment,
  parseArgs,
  parseProcessTable,
  resolvePolicy,
}
