#!/usr/bin/env node
/**
 * Report local Beads/Dolt storage that can make every tracker command slow.
 *
 * Embedded Dolt opens every visible database below its data directory. An old
 * sibling database can therefore add seconds and gigabytes of memory even when
 * the active issue database is healthy. This command is deliberately read-only:
 * it identifies active, sibling, and already-dropped databases, then points the
 * maintainer to the reviewed recovery procedure instead of deleting data.
 */

'use strict'

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const WARNING_EXIT_CODE = 2

function usage() {
  console.log(`Usage: node scripts/dev/check-beads-storage.js [options]

Options:
  --root <path>  Repository root to inspect (default: current directory)
  --json         Emit a machine-readable report
  -h, --help     Show this help

This command never changes the Beads database.`)
}

function fail(message) {
  throw new Error(message)
}

function parseArgs(argv) {
  const options = { root: process.cwd(), json: false, help: false }
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '-h' || arg === '--help') {
      options.help = true
      continue
    }
    if (arg === '--json') {
      options.json = true
      continue
    }
    if (arg === '--root') {
      if (index + 1 >= argv.length) fail('--root requires a path')
      options.root = argv[index + 1]
      index += 1
      continue
    }
    fail(`unknown option: ${arg}`)
  }
  options.root = path.resolve(options.root)
  return options
}

function directorySizeKiB(directory) {
  if (!fs.existsSync(directory)) return 0
  const result = spawnSync('du', ['-sk', directory], { encoding: 'utf8' })
  if (result.status !== 0) {
    fail(`could not measure ${directory}: ${String(result.stderr || '').trim()}`)
  }
  const value = Number.parseInt(String(result.stdout).trim().split(/\s+/, 1)[0], 10)
  if (!Number.isFinite(value)) fail(`could not parse disk usage for ${directory}`)
  return value
}

function readBdVersion() {
  const result = spawnSync(process.env.HXHX_BEADS_STORAGE_BD_BIN || 'bd', ['version'], {
    encoding: 'utf8',
  })
  if (result.status !== 0) return 'unavailable'
  return String(result.stdout).trim() || 'unknown'
}

function formatMiB(kib) {
  return `${(kib / 1024).toFixed(1)} MiB`
}

function inspect(options) {
  const beadsDir = path.join(options.root, '.beads')
  const metadataPath = path.join(beadsDir, 'metadata.json')
  const dataDir = path.join(beadsDir, 'embeddeddolt')

  if (!fs.existsSync(metadataPath) || !fs.existsSync(dataDir)) {
    return {
      status: 'skip',
      reason: 'not_initialized',
      root: options.root,
      beadsVersion: readBdVersion(),
    }
  }

  let metadata
  try {
    metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'))
  } catch (error) {
    fail(`cannot parse ${metadataPath}: ${error.message}`)
  }

  const activeDatabase = String(metadata.dolt_database || '').trim()
  if (!activeDatabase) fail(`${metadataPath} does not name dolt_database`)

  const databases = fs
    .readdirSync(dataDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
    .map((entry) => ({
      name: entry.name,
      sizeKiB: directorySizeKiB(path.join(dataDir, entry.name)),
    }))
    .sort((left, right) => left.name.localeCompare(right.name))

  const siblingDatabases = databases.filter((database) => database.name !== activeDatabase)
  const active = databases.find((database) => database.name === activeDatabase)
  const droppedSizeKiB = directorySizeKiB(path.join(dataDir, '.dolt_dropped_databases'))
  const totalSizeKiB = directorySizeKiB(beadsDir)

  if (!active) {
    return {
      status: 'fail',
      reason: 'active_database_missing',
      root: options.root,
      beadsVersion: readBdVersion(),
      activeDatabase,
      databases,
      siblingDatabases,
      droppedSizeKiB,
      totalSizeKiB,
    }
  }

  return {
    status: siblingDatabases.length > 0 || droppedSizeKiB > 0 ? 'warn' : 'pass',
    reason:
      siblingDatabases.length > 0
        ? 'sibling_databases'
        : droppedSizeKiB > 0
          ? 'dropped_database_storage'
          : 'healthy',
    root: options.root,
    beadsVersion: readBdVersion(),
    activeDatabase,
    activeSizeKiB: active.sizeKiB,
    databases,
    siblingDatabases,
    droppedSizeKiB,
    totalSizeKiB,
  }
}

function printHuman(report) {
  if (report.status === 'skip') {
    console.log('Beads storage check: no local embedded database is initialized.')
    console.log('BEADS_STORAGE_CHECK:SKIP reason=not_initialized')
    return
  }

  console.log('Beads storage check')
  console.log(`  Beads: ${report.beadsVersion}`)
  console.log(`  active database: ${report.activeDatabase}`)
  if (report.activeSizeKiB != null) console.log(`  active size: ${formatMiB(report.activeSizeKiB)}`)
  console.log(`  total .beads size: ${formatMiB(report.totalSizeKiB)}`)
  console.log(
    `  sibling databases: ${report.siblingDatabases.length > 0 ? report.siblingDatabases.map((item) => item.name).join(', ') : 'none'}`,
  )
  console.log(`  dropped-database storage: ${formatMiB(report.droppedSizeKiB)}`)

  if (report.status === 'pass') {
    console.log(
      `BEADS_STORAGE_CHECK:PASS active_database=${report.activeDatabase} sibling_databases=0 dropped_kib=0`,
    )
    return
  }

  if (report.status === 'warn') {
    console.error(
      'Beads storage needs review. This command will not delete anything; follow the backup-first procedure in TESTING.md.',
    )
    console.error(
      `BEADS_STORAGE_CHECK:WARN reason=${report.reason} sibling_databases=${report.siblingDatabases.map((item) => item.name).join(',') || 'none'} dropped_kib=${report.droppedSizeKiB}`,
    )
    return
  }

  console.error(`BEADS_STORAGE_CHECK:FAIL reason=${report.reason} active_database=${report.activeDatabase}`)
}

function main() {
  try {
    const options = parseArgs(process.argv.slice(2))
    if (options.help) {
      usage()
      return
    }
    const report = inspect(options)
    if (options.json) console.log(JSON.stringify(report, null, 2))
    else printHuman(report)

    if (report.status === 'warn') process.exitCode = WARNING_EXIT_CODE
    else if (report.status === 'fail') process.exitCode = 1
  } catch (error) {
    console.error(`BEADS_STORAGE_CHECK:FAIL ${error.message}`)
    process.exitCode = 1
  }
}

main()
