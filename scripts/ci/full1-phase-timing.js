#!/usr/bin/env node
/**
 * Append and summarize Full1 CI phase timing records.
 *
 * Heavy Full1 workflows need stable phase timings so throughput changes can be
 * compared from artifacts instead of eyeballing GitHub log timestamps.
 */

const fs = require('fs')
const path = require('path')

function fail(message) {
  console.error(`[full1-phase-timing] ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const command = argv[0] || ''
  const out = { command }
  for (let i = 1; i < argv.length; i += 1) {
    const arg = argv[i]
    if (!arg.startsWith('--')) {
      fail(`unexpected positional argument: ${arg}`)
    }
    const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())
    const value = argv[i + 1]
    if (value == null || value.startsWith('--')) {
      fail(`missing value for ${arg}`)
    }
    out[key] = value
    i += 1
  }
  return out
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true })
}

function readRecords(jsonlPath) {
  if (!fs.existsSync(jsonlPath)) {
    return []
  }
  return fs.readFileSync(jsonlPath, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line))
}

function appendRecord(args) {
  const required = ['jsonl', 'workflow', 'job', 'phase', 'startedMs', 'endedMs', 'status', 'exitCode']
  for (const key of required) {
    if (!args[key]) {
      fail(`append requires --${key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`)
    }
  }

  const startedMs = Number(args.startedMs)
  const endedMs = Number(args.endedMs)
  const exitCode = Number(args.exitCode)
  if (!Number.isFinite(startedMs) || !Number.isFinite(endedMs)) {
    fail('started/ended timestamps must be numeric milliseconds')
  }
  if (!Number.isFinite(exitCode)) {
    fail('exit code must be numeric')
  }

  const record = {
    schema: 'full1-phase-timing-record.v1',
    workflow: args.workflow,
    job: args.job,
    phase: args.phase,
    status: args.status,
    exit_code: exitCode,
    started_at: new Date(startedMs).toISOString(),
    ended_at: new Date(endedMs).toISOString(),
    duration_ms: Math.max(0, endedMs - startedMs),
  }
  if (args.detail) {
    record.detail = args.detail
  }

  ensureParent(args.jsonl)
  fs.appendFileSync(args.jsonl, `${JSON.stringify(record)}\n`, 'utf8')
  console.log(`[full1-phase-timing] phase=${record.phase} status=${record.status} duration_ms=${record.duration_ms}`)
}

function summarize(args) {
  const required = ['jsonl', 'jsonOut', 'markdownOut']
  for (const key of required) {
    if (!args[key]) {
      fail(`summarize requires --${key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`)
    }
  }

  const records = readRecords(args.jsonl)
  const totalDurationMs = records.reduce((sum, record) => sum + Number(record.duration_ms || 0), 0)
  const failed = records.filter((record) => record.status !== 'pass' || Number(record.exit_code || 0) !== 0)
  const summary = {
    schema: 'full1-phase-timing-summary.v1',
    source: path.resolve(args.jsonl),
    workflow: records[0] ? records[0].workflow : '',
    job: records[0] ? records[0].job : '',
    phase_count: records.length,
    total_duration_ms: totalDurationMs,
    failed_phase_count: failed.length,
    phases: records,
  }

  ensureParent(args.jsonOut)
  ensureParent(args.markdownOut)
  fs.writeFileSync(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`, 'utf8')

  const lines = [
    `### Full1 phase timings: ${summary.job || 'unknown job'}`,
    '',
    '| Phase | Status | Exit | Duration (s) |',
    '| --- | --- | ---: | ---: |',
  ]
  for (const record of records) {
    const seconds = (Number(record.duration_ms || 0) / 1000).toFixed(3)
    lines.push(`| ${record.phase} | ${record.status} | ${record.exit_code} | ${seconds} |`)
  }
  lines.push('')
  lines.push(`Total measured phase time: ${(totalDurationMs / 1000).toFixed(3)}s`)
  fs.writeFileSync(args.markdownOut, `${lines.join('\n')}\n`, 'utf8')
  console.log(`[full1-phase-timing] summary=${args.jsonOut}`)
}

const args = parseArgs(process.argv.slice(2))
if (args.command === 'append') {
  appendRecord(args)
} else if (args.command === 'summarize') {
  summarize(args)
} else {
  fail('expected command: append|summarize')
}
