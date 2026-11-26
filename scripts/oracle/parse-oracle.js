#!/usr/bin/env node
'use strict'

/**
 * Frontend parse oracle: compare how hxhx and upstream Haxe 4.3.7 parse the same Haxe files.
 *
 * Why
 *   hxhx targets upstream Haxe 4.3.7 behaviour, and its frontend needs a direct progress number.
 *   This compares the parsed body of every field (function bodies and field initializers) in a
 *   corpus, after the same conditional compilation, printed with haxe.macro.Printer.
 *   See docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md (milestone B1, bead haxe_ocaml-7cxgt).
 *
 * How
 *   1. Upstream Haxe compiles the corpus for the interp target with a global build macro
 *      (scripts/oracle/upstream) that records each field body. Upstream is a black box.
 *   2. hxhx-core, running under `haxe --run`, parses the same files with the recorded defines
 *      and exports the same bodies (scripts/oracle/ParseOracleHxhx.hx).
 *   3. Both sides use scripts/oracle/shared/ParseOracleNormalize.hx, so only spellings that
 *      cannot change meaning are ignored.
 *
 * Usage
 *   node scripts/oracle/parse-oracle.js [--out DIR] [--package PKG]... [--exclude MODULE]... [--check-baseline]
 *   Defaults: the `haxe` package of the upstream standard library, excluding haxe.atomic.
 *   Prints `PARSE_ORACLE: ...` and writes report.json and mismatches.txt to DIR.
 *   --check-baseline fails when the matching field or file count falls below
 *   scripts/oracle/parse-oracle-baseline.json, and asks for the baseline to be raised when it improves.
 */

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')

function parseArgs(argv) {
  const options = { out: path.join(root, '.tmp/parse-oracle'), packages: [], excludes: [], haxe: process.env.HAXE_BIN || 'haxe', checkBaseline: false }
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
    else if (arg === '--help') {
      console.log('Usage: node scripts/oracle/parse-oracle.js [--out DIR] [--package PKG]... [--exclude MODULE]...')
      process.exit(0)
    } else throw new Error(`unknown argument: ${arg}`)
  }
  if (options.packages.length === 0) {
    options.packages = ['haxe']
    if (options.excludes.length === 0) options.excludes = ['haxe.atomic']
  }
  return options
}

function run(haxe, args, label) {
  const result = spawnSync(haxe, args, { cwd: root, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 })
  if (result.status !== 0) {
    throw new Error(`${label} failed (status ${result.status}, signal ${result.signal}):\n${result.stdout}${result.stderr}`)
  }
}

function quote(value) {
  return `'${value.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`
}

/**
 * Give the second and later records with one key an ordinal suffix (`key#2`), in record order.
 * Overloads share a name (haxe.ds.Vector declares two constructors); both sides record them in
 * declaration order, so the suffix pairs them. A pair still matches only when the bodies are equal.
 */
function withOrdinals(records) {
  const seen = new Map()
  return records.map(record => {
    const count = (seen.get(record.key) || 0) + 1
    seen.set(record.key, count)
    return count === 1 ? record : { ...record, key: `${record.key}#${count}` }
  })
}

function compare(upstreamDump, hxhxDump) {
  const upstream = { ...upstreamDump, records: withOrdinals(upstreamDump.records) }
  const hxhx = { ...hxhxDump, records: withOrdinals(hxhxDump.records) }
  const byKey = new Map(hxhx.records.map(record => [record.key, record]))
  const counts = { match: 0, mismatch: 0, missingInHxhx: 0, hxhxExportError: 0, upstreamError: 0 }
  const files = new Map()
  const mismatches = []
  const exportErrors = new Map()
  for (const record of upstream.records) {
    const file = files.get(record.file) || { total: 0, match: 0 }
    files.set(record.file, file)
    if (record.error) {
      counts.upstreamError++
      continue
    }
    file.total++
    const other = byKey.get(record.key)
    if (!other) counts.missingInHxhx++
    else if (other.error) {
      counts.hxhxExportError++
      const reason = other.error.slice(0, 120)
      exportErrors.set(reason, (exportErrors.get(reason) || 0) + 1)
    } else if (other.body === record.body) {
      counts.match++
      file.match++
    } else {
      counts.mismatch++
      mismatches.push({ key: record.key, upstream: record.body, hxhx: other.body })
    }
  }
  const compared = upstream.records.length - counts.upstreamError
  const fileList = [...files.values()].filter(file => file.total > 0)
  const fullFiles = fileList.filter(file => file.match === file.total).length
  // Bodies only hxhx has. Informational: they count toward no field, match, file or baseline number.
  // `lowering` marks members that hxhx's enum lowering adds (see ParseOracleHxhx.loweredMembers).
  const upstreamKeys = new Set(upstream.records.map(record => record.key))
  const extras = hxhx.records.filter(record => !upstreamKeys.has(record.key))
  return {
    counts,
    hxhxOnly: extras.filter(record => !record.lowering).map(record => record.key),
    hxhxOnlyLowering: extras.filter(record => record.lowering).map(record => record.key),
    comparedFields: compared,
    fieldMatchPercent: compared === 0 ? 0 : (100 * counts.match) / compared,
    files: fileList.length,
    fullyMatchingFiles: fullFiles,
    fileMatchPercent: fileList.length === 0 ? 0 : (100 * fullFiles) / fileList.length,
    hxhxFileParseErrors: hxhx.fileErrors,
    exportErrors: [...exportErrors.entries()].sort((a, b) => b[1] - a[1]).map(([reason, count]) => ({ reason, count })),
    mismatches
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2))
  fs.mkdirSync(options.out, { recursive: true })
  const upstreamJson = path.join(options.out, 'upstream.json')
  const hxhxJson = path.join(options.out, 'hxhx.json')
  const excludes = `[${options.excludes.map(quote).join(', ')}]`
  const includeMacros = options.packages.flatMap(pkg => ['--macro', `include(${quote(pkg)}, true, ${excludes})`])
  run(options.haxe, ['-cp', 'scripts/oracle/upstream', '-cp', 'scripts/oracle/shared', '--macro', `ParseOracleUpstream.install(${quote(upstreamJson)})`, ...includeMacros, '--interp', '--no-output'], 'upstream parse dump')
  run(options.haxe, ['-cp', 'packages/hxhx-core/src', '-cp', 'packages/reflaxe.ocaml/src', '-cp', 'packages/hxhx/src', '-cp', 'scripts/oracle', '-cp', 'scripts/oracle/shared', '--run', 'ParseOracleHxhx', upstreamJson, hxhxJson], 'hxhx parse dump')
  const report = compare(JSON.parse(fs.readFileSync(upstreamJson, 'utf8')), JSON.parse(fs.readFileSync(hxhxJson, 'utf8')))
  report.corpus = { packages: options.packages, excludes: options.excludes, target: 'interp' }
  fs.writeFileSync(path.join(options.out, 'report.json'), JSON.stringify(report, null, 2))
  fs.writeFileSync(
    path.join(options.out, 'mismatches.txt'),
    report.mismatches.map(item => `===== ${item.key}\n--- upstream\n${item.upstream}\n--- hxhx\n${item.hxhx}\n`).join('\n')
  )
  const c = report.counts
  console.log(
    `PARSE_ORACLE: fields=${report.comparedFields} match=${c.match} (${report.fieldMatchPercent.toFixed(1)}%) mismatch=${c.mismatch} ` +
      `missing=${c.missingInHxhx} export_error=${c.hxhxExportError} files=${report.files} fully_matching=${report.fullyMatchingFiles} ` +
      `(${report.fileMatchPercent.toFixed(1)}%) hxhx_file_parse_errors=${report.hxhxFileParseErrors.length} ` +
      `hxhx_only=${report.hxhxOnly.length} hxhx_only_lowering=${report.hxhxOnlyLowering.length}`
  )
  console.log(`[parse-oracle] report: ${path.relative(root, path.join(options.out, 'report.json'))}`)
  if (options.checkBaseline) checkBaseline(report)
}

/** Keep the default corpus from losing matches; a gain should raise the recorded baseline. */
function checkBaseline(report) {
  const baselinePath = path.join(__dirname, 'parse-oracle-baseline.json')
  const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'))
  const failures = []
  if (report.counts.match < baseline.matchingFields) failures.push(`matching fields ${report.counts.match} < baseline ${baseline.matchingFields}`)
  if (report.fullyMatchingFiles < baseline.fullyMatchingFiles) failures.push(`fully matching files ${report.fullyMatchingFiles} < baseline ${baseline.fullyMatchingFiles}`)
  if (failures.length > 0) throw new Error(`parse oracle regressed: ${failures.join('; ')}`)
  if (report.counts.match > baseline.matchingFields || report.fullyMatchingFiles > baseline.fullyMatchingFiles) {
    console.log(`[parse-oracle] improved: raise ${path.relative(root, baselinePath)} to matchingFields=${report.counts.match} fullyMatchingFiles=${report.fullyMatchingFiles}`)
  }
  console.log('PARSE_ORACLE_BASELINE:PASS')
}

try {
  main()
} catch (error) {
  console.error(`[parse-oracle] ERROR: ${error.message}`)
  process.exit(1)
}
