#!/usr/bin/env node
/**
 * Summarize strict Cpp render timing frontiers across one or more logs.
 *
 * This is a diagnostic helper for Full1 Cpp burn-down. It does not decide
 * correctness and should not be used to justify semantic/runtime changes by
 * itself. Its job is to make moving timeout frontiers visible before the next
 * focused patch is selected.
 */

const fs = require('fs')

function fail(message) {
  console.error(`[cpp-strict-frontier-summary] ERROR: ${message}`)
  process.exit(1)
}

function parsePositiveInt(raw, label) {
  const value = Number(raw)
  if (!Number.isInteger(value) || value <= 0) fail(`${label} must be a positive integer: ${raw}`)
  return value
}

function parseArgs(argv) {
  const options = {
    top: 10,
    minRepeat: 2,
    jsonOut: null,
    logs: []
  }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--top') {
      options.top = parsePositiveInt(argv[++i], '--top')
    } else if (arg === '--min-repeat') {
      options.minRepeat = parsePositiveInt(argv[++i], '--min-repeat')
    } else if (arg === '--json-out') {
      options.jsonOut = argv[++i]
      if (!options.jsonOut) fail('--json-out requires a path')
    } else if (arg === '--help' || arg === '-h') {
      console.log([
        'usage: node scripts/ci/cpp-strict-frontier-summary.js [options] <log>...',
        '',
        'options:',
        '  --top <n>          Number of top timing entries to compare per log (default: 10)',
        '  --min-repeat <n>   Count required to call an entry repeated (default: 2)',
        '  --json-out <path>  Write machine-readable summary JSON'
      ].join('\n'))
      process.exit(0)
    } else if (arg.startsWith('--')) {
      fail(`unknown option: ${arg}`)
    } else {
      options.logs.push(arg)
    }
  }
  if (options.logs.length === 0) fail('at least one log path is required')
  if (options.minRepeat > options.logs.length) {
    fail(`--min-repeat (${options.minRepeat}) cannot exceed log count (${options.logs.length})`)
  }
  return options
}

function eventId(event) {
  return `${event.kind}:${event.owner ? `${event.owner}.` : ''}${event.name}`
}

function parseSeconds(raw) {
  const value = Number(raw)
  return Number.isFinite(value) ? value : 0
}

function parseLog(logPath, top) {
  if (!fs.existsSync(logPath)) fail(`missing log: ${logPath}`)
  const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/)
  const events = []
  let probeExit = null
  let elapsed = null

  lines.forEach((line, index) => {
    const lineNumber = index + 1
    const probeMatch = line.match(/probe_exit=(\d+)\s+elapsed=([0-9.]+)s/)
    if (probeMatch) {
      probeExit = Number(probeMatch[1])
      elapsed = Number(probeMatch[2])
    }

    const classMatch = line.match(/render_helper_class_timing name=([^ ]+) seconds=([^ ]+) lines=([^ ]+)/)
    if (classMatch) {
      events.push({
        kind: 'class',
        name: classMatch[1],
        seconds: parseSeconds(classMatch[2]),
        renderedLines: Number(classMatch[3]),
        lineNumber
      })
      return
    }

    const methodMatch = line.match(/render_helper_method_timing owner=([^ ]+) name=([^ ]+) seconds=([^ ]+) lines=([^ ]+)/)
    if (methodMatch) {
      events.push({
        kind: 'method',
        owner: methodMatch[1],
        name: methodMatch[2],
        seconds: parseSeconds(methodMatch[3]),
        renderedLines: Number(methodMatch[4]),
        lineNumber
      })
    }
  })

  const topTimings = events.slice().sort((left, right) => right.seconds - left.seconds).slice(0, top)
  return {
    path: logPath,
    probeExit,
    elapsed,
    eventCount: events.length,
    lastEvent: events.length > 0 ? events[events.length - 1] : null,
    topTimings
  }
}

function countEntries(logs, selector) {
  const counts = new Map()
  for (const log of logs) {
    const ids = new Set(selector(log).filter(Boolean))
    for (const id of ids) counts.set(id, (counts.get(id) || 0) + 1)
  }
  return [...counts.entries()]
    .map(([id, count]) => ({id, count}))
    .sort((left, right) => right.count - left.count || left.id.localeCompare(right.id))
}

function classify(logs, minRepeat) {
  if (logs.length < minRepeat) return 'single-log'
  const repeatedFrontiers = countEntries(logs, log => [log.lastEvent ? eventId(log.lastEvent) : null])
    .filter(entry => entry.count >= minRepeat)
  if (repeatedFrontiers.length > 0) return 'repeated-frontier'
  const repeatedTopTimings = countEntries(logs, log => log.topTimings.map(eventId)).filter(entry => entry.count >= minRepeat)
  if (repeatedTopTimings.length > 0) return 'shared-hotspots-moving-frontier'
  return 'moving-frontier'
}

function buildSummary(options) {
  const logs = options.logs.map(logPath => parseLog(logPath, options.top))
  const frontierCounts = countEntries(logs, log => [log.lastEvent ? eventId(log.lastEvent) : null])
  const repeatedFrontiers = frontierCounts.filter(entry => entry.count >= options.minRepeat)
  const topTimingCounts = countEntries(logs, log => log.topTimings.map(eventId))
  const repeatedTopTimings = topTimingCounts.filter(entry => entry.count >= options.minRepeat)
  return {
    schema: 'cpp-strict-frontier-summary.v1',
    marker: 'CPP_STRICT_FRONTIER_SUMMARY:PASS',
    classification: classify(logs, options.minRepeat),
    top: options.top,
    minRepeat: options.minRepeat,
    logs,
    repeatedFrontiers,
    repeatedTopTimings
  }
}

function formatEvent(event) {
  if (!event) return '(none)'
  const name = event.owner ? `${event.owner}.${event.name}` : event.name
  return `${event.kind}:${name} seconds=${event.seconds} line=${event.lineNumber}`
}

function printSummary(summary) {
  console.log(`${summary.marker} classification=${summary.classification} logs=${summary.logs.length} min_repeat=${summary.minRepeat}`)
  for (const log of summary.logs) {
    console.log(`log=${log.path}`)
    console.log(`  events=${log.eventCount} probe_exit=${log.probeExit == null ? 'unknown' : log.probeExit} elapsed=${log.elapsed == null ? 'unknown' : log.elapsed}`)
    console.log(`  last=${formatEvent(log.lastEvent)}`)
    for (const event of log.topTimings.slice(0, Math.min(5, log.topTimings.length))) {
      console.log(`  top=${formatEvent(event)}`)
    }
  }
  const frontiers = summary.repeatedFrontiers.map(entry => `${entry.id}(${entry.count})`).join(', ') || 'none'
  const hotspots = summary.repeatedTopTimings.slice(0, 10).map(entry => `${entry.id}(${entry.count})`).join(', ') || 'none'
  console.log(`repeated_frontiers=${frontiers}`)
  console.log(`repeated_top_timings=${hotspots}`)
  if (summary.classification === 'repeated-frontier') {
    console.log('recommendation=run a method-filtered probe for the repeated frontier before patching')
  } else if (summary.classification === 'shared-hotspots-moving-frontier') {
    console.log('recommendation=prefer shared top timings or repeat probes; do not patch the last timeout boundary alone')
  } else {
    console.log('recommendation=record variance or repeat diagnostics before selecting a semantic/render seam')
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2))
  const summary = buildSummary(options)
  if (options.jsonOut) fs.writeFileSync(options.jsonOut, JSON.stringify(summary, null, 2) + '\n')
  printSummary(summary)
}

if (require.main === module) main()

module.exports = {
  buildSummary,
  parseLog,
  eventId
}
