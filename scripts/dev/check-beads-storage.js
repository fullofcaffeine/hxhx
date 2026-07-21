#!/usr/bin/env node
/**
 * Report local Beads/Dolt storage that can make every tracker command slow.
 *
 * Embedded Dolt opens every visible database below its data directory. An old
 * sibling database can therefore add seconds and gigabytes of memory, while a
 * single active database can accumulate enough local change history to exhaust
 * disk space. This command is deliberately read-only: it identifies both
 * shapes, reports whether safe maintenance headroom exists, and points the
 * maintainer to the reviewed recovery procedure instead of deleting data.
 */

'use strict'

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

// A healthy post-maintenance checkout used about 67 MiB for the active
// database and 217 MiB for all local Beads state. These deliberately earlier
// review thresholds leave room to make a backup before history growth becomes
// an emergency.
const ACTIVE_DATABASE_REVIEW_KIB = 256 * 1024
const TOTAL_BEADS_REVIEW_KIB = 512 * 1024
const MIN_MAINTENANCE_HEADROOM_KIB = 1024 * 1024
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
  const result = spawnSync(process.env.HXHX_BEADS_STORAGE_DU_BIN || 'du', ['-sk', directory], {
    encoding: 'utf8',
  })
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

/**
 * Report available space without making it a correctness dependency.
 *
 * Maintenance still needs a verified backup and an isolated trial. This value
 * only prevents the doctor from recommending a rewrite when the live volume
 * cannot safely hold the temporary copy.
 */
function readAvailableFilesystemKiB(root) {
  try {
    const stats = fs.statfsSync(root)
    const bytes = Number(stats.bavail) * Number(stats.bsize)
    if (!Number.isFinite(bytes) || bytes < 0) return null
    return Math.floor(bytes / 1024)
  } catch (_error) {
    return null
  }
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
  const backupSizeKiB = directorySizeKiB(path.join(beadsDir, 'backup'))
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
      backupSizeKiB,
      totalSizeKiB,
    }
  }

  const filesystemAvailableKiB = readAvailableFilesystemKiB(options.root)
  const maintenanceHeadroomKiB = Math.max(MIN_MAINTENANCE_HEADROOM_KIB, active.sizeKiB * 2)
  const maintenanceHeadroomSufficient =
    filesystemAvailableKiB === null ? null : filesystemAvailableKiB >= maintenanceHeadroomKiB
  const reasons = []

  if (siblingDatabases.length > 0) reasons.push('sibling_databases')
  if (droppedSizeKiB > 0) reasons.push('dropped_database_storage')
  if (active.sizeKiB >= ACTIVE_DATABASE_REVIEW_KIB) reasons.push('active_database_storage')
  if (totalSizeKiB >= TOTAL_BEADS_REVIEW_KIB) reasons.push('total_beads_storage')

  return {
    status: reasons.length > 0 ? 'warn' : 'pass',
    reason: reasons.length > 0 ? reasons[0] : 'healthy',
    reasons,
    root: options.root,
    beadsVersion: readBdVersion(),
    activeDatabase,
    activeSizeKiB: active.sizeKiB,
    activeDatabaseReviewKiB: ACTIVE_DATABASE_REVIEW_KIB,
    totalBeadsReviewKiB: TOTAL_BEADS_REVIEW_KIB,
    databases,
    siblingDatabases,
    droppedSizeKiB,
    backupSizeKiB,
    totalSizeKiB,
    filesystemAvailableKiB,
    maintenanceHeadroomKiB,
    maintenanceHeadroomSufficient,
  }
}

function printHuman(report) {
  if (report.status === 'skip') {
    console.log('Beads storage check: no local embedded database is initialized.')
    console.log('BEADS_STORAGE_CHECK:SKIP reason=not_initialized')
    return
  }

  if (report.status === 'fail') {
    console.error(`BEADS_STORAGE_CHECK:FAIL reason=${report.reason} active_database=${report.activeDatabase}`)
    return
  }

  console.log('Beads storage check')
  console.log(`  Beads: ${report.beadsVersion}`)
  console.log(`  active database: ${report.activeDatabase}`)
  if (report.activeSizeKiB != null) console.log(`  active size: ${formatMiB(report.activeSizeKiB)}`)
  console.log(`  active-size review threshold: ${formatMiB(report.activeDatabaseReviewKiB)}`)
  console.log(`  local backup storage: ${formatMiB(report.backupSizeKiB)}`)
  console.log(`  total .beads size: ${formatMiB(report.totalSizeKiB)}`)
  console.log(`  total-size review threshold: ${formatMiB(report.totalBeadsReviewKiB)}`)
  console.log(
    `  sibling databases: ${report.siblingDatabases.length > 0 ? report.siblingDatabases.map((item) => item.name).join(', ') : 'none'}`,
  )
  console.log(`  dropped-database storage: ${formatMiB(report.droppedSizeKiB)}`)
  console.log(
    `  filesystem space available: ${report.filesystemAvailableKiB === null ? 'unavailable' : formatMiB(report.filesystemAvailableKiB)}`,
  )
  console.log(
    `  conservative maintenance headroom: ${formatMiB(report.maintenanceHeadroomKiB)} (${report.maintenanceHeadroomSufficient === null ? 'unknown' : report.maintenanceHeadroomSufficient ? 'available' : 'not currently available'})`,
  )

  if (report.status === 'pass') {
    console.log(
      `BEADS_STORAGE_CHECK:PASS active_database=${report.activeDatabase} active_kib=${report.activeSizeKiB} total_kib=${report.totalSizeKiB} sibling_databases=0 dropped_kib=0`,
    )
    return
  }

  if (report.status === 'warn') {
    console.error(
      'Beads storage needs review. This command will not delete anything; follow the backup-first procedure in TESTING.md.',
    )
    if (report.reasons.includes('active_database_storage')) {
      console.error(
        '  The current issue database has accumulated a large local change history even though no duplicate database is present.',
      )
    }
    if (report.maintenanceHeadroomSufficient === false) {
      console.error('  Free additional disk space before attempting a Beads backup or history compaction.')
    }
    console.error(
      `BEADS_STORAGE_CHECK:WARN reason=${report.reason} reasons=${report.reasons.join(',')} active_kib=${report.activeSizeKiB} total_kib=${report.totalSizeKiB} sibling_databases=${report.siblingDatabases.map((item) => item.name).join(',') || 'none'} dropped_kib=${report.droppedSizeKiB}`,
    )
    return
  }

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
