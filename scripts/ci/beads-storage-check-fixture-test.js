#!/usr/bin/env node
/** Prove the local Beads storage doctor stays read-only and fail-closed. */

'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const repositoryRoot = path.resolve(__dirname, '../..')
const checker = path.join(repositoryRoot, 'scripts/dev/check-beads-storage.js')
const fixtureRoots = []

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function makeFixture(name, activeDatabase = 'haxe_ocaml') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), `hxhx-beads-storage-${name}-`))
  fixtureRoots.push(root)
  const beadsDir = path.join(root, '.beads')
  const dataDir = path.join(beadsDir, 'embeddeddolt')
  fs.mkdirSync(dataDir, { recursive: true })
  fs.writeFileSync(
    path.join(beadsDir, 'metadata.json'),
    `${JSON.stringify({ backend: 'dolt', dolt_mode: 'embedded', dolt_database: activeDatabase }, null, 2)}\n`,
  )
  return { root, beadsDir, dataDir }
}

function addDatabase(fixture, name, contents = 'fixture database\n') {
  const directory = path.join(fixture.dataDir, name)
  fs.mkdirSync(directory, { recursive: true })
  fs.writeFileSync(path.join(directory, 'chunk'), contents)
}

function run(root) {
  return spawnSync(process.execPath, [checker, '--root', root], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    env: { ...process.env, HXHX_BEADS_STORAGE_BD_BIN: '/definitely/not/bd' },
  })
}

try {
  const absentRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-beads-storage-absent-'))
  fixtureRoots.push(absentRoot)
  const absent = run(absentRoot)
  assert(absent.status === 0, 'an uninitialized clone should not fail the diagnostic')
  assert(absent.stdout.includes('BEADS_STORAGE_CHECK:SKIP'), 'an uninitialized clone should emit the skip marker')

  const healthyFixture = makeFixture('healthy')
  addDatabase(healthyFixture, 'haxe_ocaml')
  const healthy = run(healthyFixture.root)
  assert(healthy.status === 0, `a single active database should pass: ${healthy.stderr}`)
  assert(healthy.stdout.includes('BEADS_STORAGE_CHECK:PASS'), 'a healthy store should emit the pass marker')
  assert(healthy.stdout.includes('active_database=haxe_ocaml'), 'the pass marker should name the active database')

  const siblingFixture = makeFixture('sibling')
  addDatabase(siblingFixture, 'haxe_ocaml')
  addDatabase(siblingFixture, 'beads')
  const sibling = run(siblingFixture.root)
  assert(sibling.status === 2, 'a sibling database should return the review-required status')
  assert(sibling.stderr.includes('reason=sibling_databases'), 'the warning should identify sibling databases')
  assert(sibling.stderr.includes('sibling_databases=beads'), 'the warning should name the sibling database')
  assert(fs.existsSync(path.join(siblingFixture.dataDir, 'beads', 'chunk')), 'the diagnostic must not delete a sibling')

  const droppedFixture = makeFixture('dropped')
  addDatabase(droppedFixture, 'haxe_ocaml')
  addDatabase({ dataDir: path.join(droppedFixture.dataDir, '.dolt_dropped_databases') }, 'old_beads')
  const dropped = run(droppedFixture.root)
  assert(dropped.status === 2, 'retained dropped-database storage should require review')
  assert(dropped.stderr.includes('reason=dropped_database_storage'), 'the warning should identify dropped storage')

  const missingFixture = makeFixture('missing', 'expected_database')
  addDatabase(missingFixture, 'different_database')
  const missing = run(missingFixture.root)
  assert(missing.status === 1, 'a missing configured database should fail closed')
  assert(missing.stderr.includes('reason=active_database_missing'), 'the failure should identify the missing active database')

  const malformedFixture = makeFixture('malformed')
  fs.writeFileSync(path.join(malformedFixture.beadsDir, 'metadata.json'), '{not-json\n')
  const malformed = run(malformedFixture.root)
  assert(malformed.status === 1, 'malformed metadata should fail closed')
  assert(malformed.stderr.includes('cannot parse'), 'malformed metadata should explain the parse failure')

  console.log('BEADS_STORAGE_CHECK_FIXTURE:PASS')
} finally {
  for (const root of fixtureRoots) fs.rmSync(root, { recursive: true, force: true })
}
