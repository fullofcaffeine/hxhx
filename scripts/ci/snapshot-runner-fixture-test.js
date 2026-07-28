#!/usr/bin/env node
/**
 * Proves that a snapshot compiler cannot consume the runner's fixture list.
 *
 * The fake compiler deliberately drains standard input. Both snapshot projects
 * must still run, which requires the parent runner to isolate compiler stdin
 * from its NUL-delimited discovery stream.
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

    console.log('SNAPSHOT_RUNNER_STDIN_ISOLATION:PASS')
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true })
  }
}

main()
