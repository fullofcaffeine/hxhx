#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const root = process.cwd()
const tradeoffsPath = 'docs/00-project/REFLAXE_PROMOTION_MATRIX_TRADEOFFS.md'
const choosePath = 'docs/01-getting-started/CHOOSE_A_REFLAXE_PROMOTION_PATH.md'
const expected = {
  'haxe-plugin': {
    result: 'RPMX_HAXE_PLUGIN:PASS',
    timingKeys: ['totalSeconds', 'compileSeconds', 'buildSeconds', 'loadProbeSeconds'],
    sourceCommit(summary) {
      return summary.source && summary.source.commit
    },
  },
  'hxhx-builtin': {
    result: 'RPMX_HXHX_BUILTIN:PASS',
    timingKeys: ['totalSeconds', 'sourceResolveSeconds', 'hxhxResolveSeconds', 'compileSeconds', 'artifactSeconds'],
    sourceCommit(summary) {
      return summary.proof && summary.proof.sourceCommit
    },
  },
  'hxhx-plugin': {
    result: 'RPMX_HXHX_PLUGIN:PASS',
    timingKeys: ['totalSeconds', 'pilotSeconds'],
    sourceCommit(summary) {
      return summary.proof && summary.proof.sourceCommit
    },
    extra(summary) {
      const breakdown = summary.timings && summary.timings.pilotBreakdown
      if (!breakdown) fail('hxhx-plugin summary is missing timings.pilotBreakdown')
      for (const key of ['totalSeconds', 'pluginPromoteSeconds', 'compileSeconds', 'nodeRunSeconds']) {
        assertPositiveNumber(breakdown[key], `hxhx-plugin timings.pilotBreakdown.${key}`)
      }
    },
  },
}

function fail(message) {
  console.error(`[rpmx-matrix-evidence] ERROR: ${message}`)
  process.exit(1)
}

function readText(relPath) {
  const abs = path.join(root, relPath)
  if (!fs.existsSync(abs)) fail(`missing file: ${relPath}`)
  return fs.readFileSync(abs, 'utf8')
}

function readJson(relPath) {
  const abs = path.join(root, relPath)
  if (!fs.existsSync(abs)) fail(`missing evidence summary: ${relPath}`)
  return JSON.parse(fs.readFileSync(abs, 'utf8'))
}

function assertPositiveNumber(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    fail(`${label} must be a positive number, got ${value}`)
  }
}

function collectEvidencePaths(tradeoffs, choose) {
  const combined = `${tradeoffs}\n${choose}`
  const matches = [...combined.matchAll(/`(\.artifacts\/rpmx\/(haxe-plugin|hxhx-builtin|hxhx-plugin)\/[^`]+?summary\.json)`/g)]
  const byKind = new Map()
  for (const match of matches) {
    const [, relPath, kind] = match
    if (!byKind.has(kind)) byKind.set(kind, relPath)
  }
  for (const kind of Object.keys(expected)) {
    if (!byKind.has(kind)) fail(`docs do not reference a ${kind} summary artifact`)
  }
  return byKind
}

function main() {
  const tradeoffs = readText(tradeoffsPath)
  const choose = readText(choosePath)
  const evidencePaths = collectEvidencePaths(tradeoffs, choose)
  const summaries = {}
  const commits = new Set()

  for (const [kind, relPath] of evidencePaths.entries()) {
    const rule = expected[kind]
    const summary = readJson(relPath)
    summaries[kind] = { path: relPath, summary }
    if (summary.result !== rule.result) {
      fail(`${kind} expected ${rule.result}, got ${summary.result || '<missing>'}`)
    }
    if (!summary.timings) fail(`${kind} summary is missing timings`)
    for (const key of rule.timingKeys) {
      assertPositiveNumber(summary.timings[key], `${kind} timings.${key}`)
    }
    const commit = rule.sourceCommit(summary)
    if (!commit || !/^[0-9a-f]{40}$/.test(commit)) {
      fail(`${kind} summary is missing a pinned 40-character source commit`)
    }
    commits.add(commit)
    if (rule.extra) rule.extra(summary)
  }

  if (commits.size !== 1) {
    fail(`expected one shared Reflaxe.elixir source commit, got ${[...commits].join(', ')}`)
  }

  const summaryOut = process.env.RPMX_MATRIX_SUMMARY_OUT
  if (summaryOut) {
    const payload = {
      marker: 'RO_PROMOTION_MATRIX:PASS',
      sourceCommit: [...commits][0],
      evidence: Object.fromEntries(
        Object.entries(summaries).map(([kind, entry]) => [
          kind,
          {
            path: entry.path,
            result: entry.summary.result,
            workload: entry.summary.workload,
            timings: entry.summary.timings,
          },
        ])
      ),
    }
    fs.mkdirSync(path.dirname(summaryOut), { recursive: true })
    fs.writeFileSync(summaryOut, JSON.stringify(payload, null, 2) + '\n')
    console.log(`rpmx_matrix_summary=${summaryOut}`)
  }

  console.log(`rpmx_matrix_source_commit=${[...commits][0]}`)
  console.log('RO_PROMOTION_MATRIX:PASS')
}

main()
