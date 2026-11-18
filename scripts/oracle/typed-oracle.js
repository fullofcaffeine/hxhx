#!/usr/bin/env node
'use strict'

/**
 * Frontend typed oracle: compare how hxhx and upstream Haxe 4.3.7 type the same Haxe modules.
 *
 * Why
 *   Milestone B1 of docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md (bead haxe_ocaml-7cxgt) needs a
 *   direct measure of typing parity next to the parse oracle. This first version compares method
 *   signatures after typing: parameter names, optional flags, and types, and the return type, with
 *   inferred types filled in.
 *
 * How
 *   1. Upstream Haxe compiles the corpus for the interp target with a macro
 *      (scripts/oracle/upstream/TypedOracleUpstream.hx) that records each typed method signature.
 *   2. hxhx-core, under `haxe --run`, parses and types the same modules with the same defines
 *      (scripts/oracle/TypedOracleHxhx.hx).
 *   3. Both sides print types in one canonical form; see the two Haxe files for the rules.
 *
 * Usage
 *   node scripts/oracle/typed-oracle.js [--out DIR] [--package PKG]... [--exclude MODULE]... [--check-baseline]
 *   Prints `TYPED_ORACLE: ...` and writes report.json and mismatches.txt to DIR.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')

function parseArgs(argv) {
  const options = { out: path.join(root, '.tmp/typed-oracle'), packages: [], excludes: [], haxe: process.env.HAXE_BIN || 'haxe', checkBaseline: false }
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index]
    const next = () => {
      if (index + 1 >= argv.length) throw new Error(`${arg} needs a value`)
      return argv[++index]
    }
    if (arg === '--out') options.out = path.resolve(next())
    else if (arg === '--package') options.packages.push(next())
    else if (arg === '--exclude') options.excludes.push(next())
    else if (arg === '--check-baseline') options.checkBaseline = true
    else throw new Error(`unknown argument: ${arg}`)
  }
  if (options.packages.length === 0) {
    options.packages = ['haxe']
    if (options.excludes.length === 0) options.excludes = ['haxe.atomic']
  }
  return options
}

function run(haxe, args, label) {
  const result = spawnSync(haxe, args, { cwd: root, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 })
  if (result.status !== 0) throw new Error(`${label} failed (status ${result.status}, signal ${result.signal}):\n${result.stdout}${result.stderr}`)
  return result.stdout
}

function quote(value) {
  return `'${value.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`
}

function standardLibraryRoot(haxe) {
  if (process.env.HAXE_STD_PATH) return process.env.HAXE_STD_PATH.split(path.delimiter)[0]
  const versioned = path.join(os.homedir(), 'haxe/versions/4.3.7/std')
  if (fs.existsSync(versioned)) return versioned
  throw new Error('cannot find the Haxe 4.3.7 standard library; set HAXE_STD_PATH')
}

function main() {
  const options = parseArgs(process.argv.slice(2))
  fs.mkdirSync(options.out, { recursive: true })
  const upstreamJson = path.join(options.out, 'upstream.json')
  const hxhxJson = path.join(options.out, 'hxhx.json')
  const excludes = `[${options.excludes.map(quote).join(', ')}]`
  const includeMacros = options.packages.flatMap(pkg => ['--macro', `include(${quote(pkg)}, true, ${excludes})`])
  run(options.haxe, ['-cp', 'scripts/oracle/upstream', '--macro', `TypedOracleUpstream.install(${quote(upstreamJson)})`, ...includeMacros, '--interp', '--no-output'], 'upstream typed dump')
  run(
    options.haxe,
    ['-cp', 'packages/hxhx-core/src', '-cp', 'packages/reflaxe.ocaml/src', '-cp', 'packages/hxhx/src', '-cp', 'scripts/oracle', '-cp', 'scripts/oracle/shared', '--run', 'TypedOracleHxhx', upstreamJson, hxhxJson, standardLibraryRoot(options.haxe)],
    'hxhx typed dump'
  )
  const upstream = JSON.parse(fs.readFileSync(upstreamJson, 'utf8'))
  const hxhx = JSON.parse(fs.readFileSync(hxhxJson, 'utf8'))
  const byKey = new Map(hxhx.records.map(record => [record.key, record]))
  const counts = { match: 0, mismatch: 0, missingInHxhx: 0, hxhxError: 0 }
  const mismatches = []
  for (const record of upstream.records) {
    const other = byKey.get(record.key)
    if (!other) counts.missingInHxhx++
    else if (other.error) counts.hxhxError++
    else if (other.signature === record.signature) counts.match++
    else {
      counts.mismatch++
      mismatches.push({ key: record.key, upstream: record.signature, hxhx: other.signature })
    }
  }
  const total = upstream.records.length
  const report = {
    corpus: { packages: options.packages, excludes: options.excludes, target: 'interp' },
    methods: total,
    counts,
    matchPercent: total === 0 ? 0 : (100 * counts.match) / total,
    moduleErrors: hxhx.moduleErrors,
    mismatches
  }
  fs.writeFileSync(path.join(options.out, 'report.json'), JSON.stringify(report, null, 2))
  fs.writeFileSync(path.join(options.out, 'mismatches.txt'), mismatches.map(item => `${item.key}\n  upstream ${item.upstream}\n  hxhx     ${item.hxhx}\n`).join('\n'))
  console.log(
    `TYPED_ORACLE: methods=${total} match=${counts.match} (${report.matchPercent.toFixed(1)}%) mismatch=${counts.mismatch} ` +
      `missing=${counts.missingInHxhx} hxhx_error=${counts.hxhxError} module_errors=${hxhx.moduleErrors.length}`
  )
  if (options.checkBaseline) {
    const baseline = JSON.parse(fs.readFileSync(path.join(__dirname, 'typed-oracle-baseline.json'), 'utf8'))
    if (counts.match < baseline.matchingMethods) throw new Error(`typed oracle regressed: matching methods ${counts.match} < baseline ${baseline.matchingMethods}`)
    if (counts.match > baseline.matchingMethods) console.log(`[typed-oracle] improved: raise scripts/oracle/typed-oracle-baseline.json to matchingMethods=${counts.match}`)
    console.log('TYPED_ORACLE_BASELINE:PASS')
  }
}

try {
  main()
} catch (error) {
  console.error(`[typed-oracle] ERROR: ${error.message}`)
  process.exit(1)
}
