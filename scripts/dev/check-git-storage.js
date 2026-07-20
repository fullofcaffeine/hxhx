#!/usr/bin/env node
/**
 * Report local Git object storage that can disable automatic maintenance.
 *
 * Large compiler and snapshot changes can leave many unreachable loose objects.
 * Git then attempts automatic cleanup during ordinary commands, and a failed
 * attempt leaves gc.log behind. This command is deliberately read-only: it
 * reports the local thresholds and storage state, then points maintainers to the
 * backup-first recovery procedure instead of pruning or repacking anything.
 */

'use strict'

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const DEFAULT_GC_AUTO = 6700
const DEFAULT_GC_AUTO_PACK_LIMIT = 50
// Git starts automatic maintenance from an object-count estimate. Large
// generated files can consume substantial disk space before that count is
// reached, so the project also owns a byte-based review threshold.
const LOOSE_SIZE_REVIEW_KIB = 256 * 1024
const MIN_MAINTENANCE_HEADROOM_KIB = 1024 * 1024
const WARNING_EXIT_CODE = 2

function usage() {
  console.log(`Usage: node scripts/dev/check-git-storage.js [options]

Options:
  --root <path>  Repository root to inspect (default: current directory)
  --json         Emit a machine-readable report
  -h, --help     Show this help

This command never changes Git objects, refs, reflogs, or configuration.`)
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

function runGit(root, args) {
  const git = process.env.HXHX_GIT_STORAGE_GIT_BIN || 'git'
  const result = spawnSync(git, ['-C', root, ...args], { encoding: 'utf8' })
  if (result.error) fail(`could not run Git: ${result.error.message}`)
  return result
}

function readGitVersion(root) {
  const result = runGit(root, ['--version'])
  if (result.status !== 0) return 'unavailable'
  return String(result.stdout).trim() || 'unknown'
}

function readIntegerConfig(root, key, fallback) {
  const result = runGit(root, ['config', '--local', '--get', key])
  if (result.status === 1) return fallback
  if (result.status !== 0) fail(`could not read ${key}: ${String(result.stderr).trim()}`)
  const value = Number.parseInt(String(result.stdout).trim(), 10)
  if (!Number.isFinite(value) || value < 0) fail(`${key} is not a non-negative integer`)
  return value
}

function readBooleanConfig(root, key) {
  const result = runGit(root, ['config', '--local', '--bool', '--get', key])
  if (result.status === 1) return false
  if (result.status !== 0) fail(`could not read ${key}: ${String(result.stderr).trim()}`)
  const value = String(result.stdout).trim()
  if (value === 'true') return true
  if (value === 'false') return false
  fail(`${key} is not a Boolean`)
}

function parseCountObjects(output) {
  const values = new Map()
  for (const line of String(output).split(/\r?\n/)) {
    const match = /^([a-z-]+):\s+(\d+)$/.exec(line.trim())
    if (match) values.set(match[1], Number.parseInt(match[2], 10))
  }

  const required = ['count', 'size', 'in-pack', 'packs', 'size-pack', 'prune-packable', 'garbage', 'size-garbage']
  for (const key of required) {
    if (!values.has(key)) fail(`git count-objects did not report ${key}`)
  }

  return {
    looseObjects: values.get('count'),
    looseSizeKiB: values.get('size'),
    packedObjects: values.get('in-pack'),
    packs: values.get('packs'),
    packedSizeKiB: values.get('size-pack'),
    prunePackable: values.get('prune-packable'),
    garbageFiles: values.get('garbage'),
    garbageSizeKiB: values.get('size-garbage'),
  }
}

function formatMiB(kib) {
  return `${(kib / 1024).toFixed(1)} MiB`
}

/**
 * Report available space without making it a correctness dependency.
 *
 * A storage doctor should still explain Git's object state when the host does
 * not expose filesystem statistics, so collection failure is represented as
 * unavailable instead of turning the whole diagnostic into an error.
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
  const version = readGitVersion(options.root)
  const gitDirResult = runGit(options.root, ['rev-parse', '--absolute-git-dir'])
  if (gitDirResult.status !== 0) {
    return {
      status: 'skip',
      reason: 'not_repository',
      root: options.root,
      gitVersion: version,
    }
  }

  const gitDir = String(gitDirResult.stdout).trim()
  if (!gitDir || !fs.existsSync(gitDir)) fail('Git reported a missing object directory')

  const countResult = runGit(options.root, ['count-objects', '-v'])
  if (countResult.status !== 0) {
    fail(`git count-objects failed: ${String(countResult.stderr).trim()}`)
  }
  const objects = parseCountObjects(countResult.stdout)
  const gcAuto = readIntegerConfig(options.root, 'gc.auto', DEFAULT_GC_AUTO)
  const gcAutoPackLimit = readIntegerConfig(options.root, 'gc.autoPackLimit', DEFAULT_GC_AUTO_PACK_LIMIT)
  const cruftPacks = readBooleanConfig(options.root, 'gc.cruftPacks')
  const gcLogPath = path.join(gitDir, 'gc.log')
  const gcLogPresent = fs.existsSync(gcLogPath) && fs.statSync(gcLogPath).size > 0
  const gcLog = gcLogPresent ? fs.readFileSync(gcLogPath, 'utf8').trim() : ''
  const filesystemAvailableKiB = readAvailableFilesystemKiB(options.root)
  const maintenanceHeadroomKiB = Math.max(MIN_MAINTENANCE_HEADROOM_KIB, objects.looseSizeKiB * 2)
  const maintenanceHeadroomSufficient =
    filesystemAvailableKiB === null ? null : filesystemAvailableKiB >= maintenanceHeadroomKiB
  const reasons = []

  if (gcLogPresent) reasons.push('gc_log')
  if (gcAuto === 0) reasons.push('automatic_gc_disabled')
  else if (objects.looseObjects > gcAuto) reasons.push('loose_object_threshold')
  if (objects.looseSizeKiB >= LOOSE_SIZE_REVIEW_KIB) reasons.push('loose_object_bytes')
  if (gcAutoPackLimit > 0 && objects.packs > gcAutoPackLimit) reasons.push('pack_threshold')
  if (objects.garbageFiles > 0 || objects.garbageSizeKiB > 0) reasons.push('garbage_files')

  return {
    status: reasons.length > 0 ? 'warn' : 'pass',
    reason: reasons.length > 0 ? reasons[0] : 'healthy',
    reasons,
    root: options.root,
    gitVersion: version,
    gitDir,
    ...objects,
    gcAuto,
    gcAutoPackLimit,
    looseSizeReviewKiB: LOOSE_SIZE_REVIEW_KIB,
    cruftPacks,
    gcLogPresent,
    gcLog,
    filesystemAvailableKiB,
    maintenanceHeadroomKiB,
    maintenanceHeadroomSufficient,
  }
}

function printHuman(report) {
  if (report.status === 'skip') {
    console.log('Git storage check: this directory is not a Git repository.')
    console.log('GIT_STORAGE_CHECK:SKIP reason=not_repository')
    return
  }

  console.log('Git storage check')
  console.log(`  Git: ${report.gitVersion}`)
  console.log(`  loose objects: ${report.looseObjects} (${formatMiB(report.looseSizeKiB)})`)
  console.log(`  packs: ${report.packs} (${formatMiB(report.packedSizeKiB)})`)
  console.log(`  automatic loose-object threshold: ${report.gcAuto}`)
  console.log(`  project loose-object size threshold: ${formatMiB(report.looseSizeReviewKiB)}`)
  console.log(`  automatic pack threshold: ${report.gcAutoPackLimit}`)
  console.log(`  cruft packs: ${report.cruftPacks ? 'enabled' : 'disabled'}`)
  console.log(`  gc.log: ${report.gcLogPresent ? 'present' : 'absent'}`)
  console.log(
    `  filesystem space available: ${report.filesystemAvailableKiB === null ? 'unavailable' : formatMiB(report.filesystemAvailableKiB)}`,
  )
  console.log(
    `  conservative maintenance headroom: ${formatMiB(report.maintenanceHeadroomKiB)} (${report.maintenanceHeadroomSufficient === null ? 'unknown' : report.maintenanceHeadroomSufficient ? 'available' : 'not currently available'})`,
  )

  if (report.status === 'pass') {
    console.log(
      `GIT_STORAGE_CHECK:PASS loose_objects=${report.looseObjects} packs=${report.packs} cruft_packs=${report.cruftPacks}`,
    )
    return
  }

  console.error(
    'Git storage needs review. This command will not prune or repack anything; follow the backup-first procedure in TESTING.md.',
  )
  if (report.reasons.includes('loose_object_bytes')) {
    console.error(
      '  Git has accumulated large unpacked file-history objects even though their count may still be below Git\'s automatic-cleanup threshold.',
    )
  }
  if (report.maintenanceHeadroomSufficient === false) {
    console.error('  Free additional disk space before attempting backup or Git maintenance in this checkout.')
  }
  if (report.gcLog) console.error(`  gc.log: ${report.gcLog.split(/\r?\n/, 1)[0]}`)
  console.error(
    `GIT_STORAGE_CHECK:WARN reasons=${report.reasons.join(',')} loose_objects=${report.looseObjects} loose_kib=${report.looseSizeKiB} packs=${report.packs}`,
  )
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
  } catch (error) {
    console.error(`GIT_STORAGE_CHECK:FAIL ${error.message}`)
    process.exitCode = 1
  }
}

main()
