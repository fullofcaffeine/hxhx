#!/usr/bin/env node
/**
 * gate3-target-summary.js
 *
 * Parses `run-upstream-runci-targets.sh` output and emits machine-readable
 * per-target status summary.
 */

const fs = require('fs')

function fail(message) {
  console.error(`[gate3-summary] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const out = {
    log: '',
    targets: '',
    jsonOut: '',
    requireNoSkip: false,
    requireAllTargets: false,
    marker: '',
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--log') {
      out.log = argv[i + 1] || ''
      i += 1
      continue
    }
    if (arg === '--targets') {
      out.targets = argv[i + 1] || ''
      i += 1
      continue
    }
    if (arg === '--json-out') {
      out.jsonOut = argv[i + 1] || ''
      i += 1
      continue
    }
    if (arg === '--marker') {
      out.marker = argv[i + 1] || ''
      i += 1
      continue
    }
    if (arg === '--require-no-skip') {
      out.requireNoSkip = true
      continue
    }
    if (arg === '--require-all-targets') {
      out.requireAllTargets = true
      continue
    }
    fail(`unknown argument: ${arg}`)
  }

  if (!out.log) fail('missing --log <path>')
  if (!out.targets) fail('missing --targets <comma-separated-list>')
  if (!out.jsonOut) fail('missing --json-out <path>')

  return out
}

function normalizeTarget(value) {
  return String(value || '').trim()
}

function parseRequestedTargets(raw) {
  const out = []
  for (const token of raw.split(',')) {
    const t = normalizeTarget(token)
    if (t.length === 0) continue
    out.push(t)
  }
  return out
}

function parseSummary(logText) {
  const entries = []
  const lines = logText.split(/\r?\n/)
  const re = /^([A-Za-z0-9_]+):\s+(PASS|FAIL|SKIP)\s+\((.*)\)$/

  for (const line of lines) {
    const m = line.match(re)
    if (m == null) continue
    entries.push({
      target: m[1],
      status: m[2],
      detail: m[3],
    })
  }

  return entries
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const logText = fs.readFileSync(args.log, 'utf8')
  const requestedTargets = parseRequestedTargets(args.targets)
  const summary = parseSummary(logText)
  const byTarget = new Map()
  for (const entry of summary) {
    byTarget.set(entry.target, entry)
  }

  const targetsRan = []
  const targetsSkipped = []
  const targetsFailed = []
  const targetsMissing = []

  for (const target of requestedTargets) {
    const entry = byTarget.get(target)
    if (entry == null) {
      targetsMissing.push(target)
      continue
    }
    targetsRan.push(target)
    if (entry.status === 'SKIP') targetsSkipped.push(target)
    if (entry.status === 'FAIL') targetsFailed.push(target)
  }

  const summaryJson = {
    schema: 'gate3-extended-summary.v1',
    targets_requested: requestedTargets,
    targets_ran: targetsRan,
    targets_skipped: targetsSkipped,
    targets_failed: targetsFailed,
    targets_missing: targetsMissing,
    entries: summary,
    strict_no_skip: args.requireNoSkip,
  }

  fs.writeFileSync(args.jsonOut, JSON.stringify(summaryJson, null, 2) + '\n', 'utf8')

  if (summary.length === 0) {
    fail('no Gate3 summary entries were found in log output')
  }
  if (args.requireAllTargets && targetsMissing.length > 0) {
    fail(`missing target summaries: ${targetsMissing.join(', ')}`)
  }
  if (args.requireNoSkip && targetsSkipped.length > 0) {
    fail(`strict mode violation: skipped targets: ${targetsSkipped.join(', ')}`)
  }
  if (targetsFailed.length > 0) {
    fail(`failing targets: ${targetsFailed.join(', ')}`)
  }

  console.log(`[gate3-summary] OK: requested=${requestedTargets.length} ran=${targetsRan.length} skipped=${targetsSkipped.length} failed=${targetsFailed.length} missing=${targetsMissing.length}`)
  if (args.marker) {
    console.log(args.marker)
  }
}

main()
