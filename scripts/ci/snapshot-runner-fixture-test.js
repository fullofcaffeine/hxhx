#!/usr/bin/env node
/**
 * Proves the snapshot runner's stream isolation and comparison boundary.
 *
 * The fake compiler deliberately drains standard input. Both snapshot projects
 * must still run, which requires the parent runner to isolate compiler stdin
 * from its NUL-delimited discovery stream. It also emits the observation-only
 * runtime-selection report, which has dedicated semantic tests and must not be
 * treated as generated-code shape.
 */

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')

function fail(message) {
  console.error(`[snapshot-runner-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function writeFixture(snapshotRoot, name) {
  const fixtureDir = path.join(snapshotRoot, name)
  const intendedDir = path.join(fixtureDir, 'intended')
  fs.mkdirSync(intendedDir, { recursive: true })
  fs.writeFileSync(path.join(fixtureDir, 'compile.hxml'), `# fake ${name} fixture\n`)
  fs.writeFileSync(path.join(intendedDir, 'Main.ml'), `let fixture_name = ${JSON.stringify(name)}\n`)
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-snapshot-runner-'))
  const snapshotRoot = path.join(tempRoot, 'snapshots')
  const runLog = path.join(tempRoot, 'compiler-runs.txt')
  const fakeHaxe = path.join(tempRoot, 'fake-haxe.sh')

  try {
    writeFixture(snapshotRoot, 'first')
    writeFixture(snapshotRoot, 'second')
    fs.writeFileSync(
      fakeHaxe,
      `#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cp -R intended out
printf '%s\\n' '{"observationOnly":true}' > out/ocaml_runtime_selection_shadow_report.json
if [[ "\${HXHX_SNAPSHOT_MUTATE_MAIN:-}" == "1" ]]; then
  printf '%s\\n' 'let fixture_name = "unexpected drift"' > out/Main.ml
fi
printf '%s\\n' "$PWD" >> "$HXHX_SNAPSHOT_RUN_LOG"
`
    )
    fs.chmodSync(fakeHaxe, 0o755)

    const result = childProcess.spawnSync('bash', [path.join(repoRoot, 'scripts', 'test-snapshots.sh')], {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HAXE_BIN: fakeHaxe,
        HXHX_SNAPSHOT_DIR: snapshotRoot,
        HXHX_SNAPSHOT_RUN_LOG: runLog
      }
    })

    if (result.error) fail(`runner could not start: ${result.error.message}`)
    if (result.status !== 0) {
      fail(`runner exited ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
    }

    const runs = fs.existsSync(runLog)
      ? fs
          .readFileSync(runLog, 'utf8')
          .trim()
          .split(/\r?\n/)
          .filter(Boolean)
      : []
    if (runs.length !== 2) {
      fail(`expected both fixtures to compile, observed ${runs.length}\nstdout:\n${result.stdout}`)
    }
    if (!result.stdout.includes(path.join(snapshotRoot, 'first'))) fail('first fixture was not reported')
    if (!result.stdout.includes(path.join(snapshotRoot, 'second'))) fail('second fixture was not reported')
    if (!result.stdout.includes('✓ Snapshots OK')) fail('runner did not print its final success marker')

    const driftResult = childProcess.spawnSync('bash', [path.join(repoRoot, 'scripts', 'test-snapshots.sh')], {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HAXE_BIN: fakeHaxe,
        HXHX_SNAPSHOT_DIR: snapshotRoot,
        HXHX_SNAPSHOT_RUN_LOG: runLog,
        HXHX_SNAPSHOT_MUTATE_MAIN: '1'
      }
    })

    if (driftResult.error) fail(`drift check could not start: ${driftResult.error.message}`)
    if (driftResult.status === 0) fail('ordinary generated OCaml drift was not rejected')
    if (!`${driftResult.stdout}\n${driftResult.stderr}`.includes('unexpected drift')) {
      fail('ordinary generated OCaml drift did not appear in the failure output')
    }

    // Run the updater in a disposable repository so a broken discovery loop
    // cannot replace the real repository's golden files during this test.
    const updateRoot = path.join(tempRoot, 'update-repo')
    const updateSnapshots = path.join(updateRoot, 'test', 'snapshot')
    const updateScript = path.join(updateRoot, 'scripts', 'update-snapshots.sh')
    const updateLog = path.join(tempRoot, 'update-runs.txt')
    fs.mkdirSync(path.dirname(updateScript), { recursive: true })
    fs.copyFileSync(path.join(repoRoot, 'scripts', 'update-snapshots.sh'), updateScript)
    for (const name of ['first', 'second']) writeFixture(updateSnapshots, name)
    const updateResult = childProcess.spawnSync('bash', [updateScript], {
      cwd: updateRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HAXE_BIN: fakeHaxe,
        HXHX_SNAPSHOT_RUN_LOG: updateLog,
        HXHX_SNAPSHOT_MUTATE_MAIN: '1'
      }
    })
    if (updateResult.error) fail(`updater could not start: ${updateResult.error.message}`)
    if (updateResult.status !== 0) fail(`updater exited ${updateResult.status}\n${updateResult.stderr}`)
    for (const name of ['first', 'second']) {
      const actual = fs.readFileSync(path.join(updateSnapshots, name, 'intended', 'Main.ml'), 'utf8')
      if (actual !== 'let fixture_name = "unexpected drift"\n') {
        fail(`updater did not regenerate ${name}\nstdout:\n${updateResult.stdout}`)
      }
    }

    const scopedSnapshots = path.join(tempRoot, 'scoped-snapshots')
    writeFixture(scopedSnapshots, 'selected')
    const untouched = path.join(updateSnapshots, 'first', 'intended', 'Main.ml')
    fs.writeFileSync(untouched, 'let untouched = true\n')
    const scopedResult = childProcess.spawnSync('bash', [updateScript], {
      cwd: updateRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HAXE_BIN: fakeHaxe,
        HXHX_SNAPSHOT_DIR: scopedSnapshots,
        HXHX_SNAPSHOT_RUN_LOG: path.join(tempRoot, 'scoped-runs.txt'),
        HXHX_SNAPSHOT_MUTATE_MAIN: '1'
      }
    })
    if (scopedResult.error || scopedResult.status !== 0) fail('scoped updater did not complete')
    if (fs.readFileSync(path.join(scopedSnapshots, 'selected', 'intended', 'Main.ml'), 'utf8') !== 'let fixture_name = "unexpected drift"\n') {
      fail('scoped updater did not regenerate the selected fixture')
    }
    if (fs.readFileSync(untouched, 'utf8') !== 'let untouched = true\n') {
      fail('scoped updater changed a fixture outside its selected directory')
    }

    console.log('SNAPSHOT_RUNNER_BOUNDARY:PASS')
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true })
  }
}

main()
