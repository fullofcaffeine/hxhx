#!/usr/bin/env node
/**
 * Fixture tests for cpp-strict-frontier-summary.js.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const childProcess = require('child_process')

const repoRoot = process.cwd()
const script = path.join(repoRoot, 'scripts/ci/cpp-strict-frontier-summary.js')

function fail(message) {
  console.error(`[cpp-strict-frontier-summary-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function writeLog(dir, name, lines) {
  const filePath = path.join(dir, name)
  fs.writeFileSync(filePath, lines.join('\n') + '\n')
  return filePath
}

function runCase(tmpDir, name, logs, expectedClassification, expectedText) {
  const jsonOut = path.join(tmpDir, `${name}.json`)
  const result = childProcess.spawnSync(process.execPath, [script, '--top', '3', '--json-out', jsonOut, ...logs], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== 0) {
    fail(`${name}: expected exit 0, got ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  if (!String(result.stdout).includes('CPP_STRICT_FRONTIER_SUMMARY:PASS')) {
    fail(`${name}: missing pass marker in stdout`)
  }
  if (expectedText && !String(result.stdout).includes(expectedText)) {
    fail(`${name}: stdout did not include ${expectedText}\nstdout:\n${result.stdout}`)
  }
  if (!fs.existsSync(jsonOut)) fail(`${name}: missing JSON summary`)
  const summary = JSON.parse(fs.readFileSync(jsonOut, 'utf8'))
  if (summary.classification !== expectedClassification) {
    fail(`${name}: expected ${expectedClassification}, got ${summary.classification}`)
  }
  return summary
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cpp-strict-frontier-summary-fixtures-'))
  try {
    const repeatedA = writeLog(tmpDir, 'repeated-a.log', [
      'cpp_target_phase=render_helper_class_timing name=Alpha seconds=1.0 lines=3',
      'cpp_target_phase=render_helper_method_timing owner=Hot name=frontier seconds=2.0 lines=4'
    ])
    const repeatedB = writeLog(tmpDir, 'repeated-b.log', [
      'cpp_target_phase=render_helper_class_timing name=Beta seconds=1.5 lines=3',
      'cpp_target_phase=render_helper_method_timing owner=Hot name=frontier seconds=2.5 lines=4'
    ])
    const repeatedSummary = runCase(tmpDir, 'repeated', [repeatedA, repeatedB], 'repeated-frontier', 'repeated_frontiers=method:Hot.frontier(2)')
    if (repeatedSummary.repeatedFrontiers.length !== 1) fail('repeated: expected one repeated frontier')

    const sharedA = writeLog(tmpDir, 'shared-a.log', [
      'cpp_target_phase=render_helper_class_timing name=Shared seconds=5.0 lines=3',
      'cpp_target_phase=render_helper_method_timing owner=A name=end seconds=1.0 lines=4'
    ])
    const sharedB = writeLog(tmpDir, 'shared-b.log', [
      'cpp_target_phase=render_helper_class_timing name=Shared seconds=6.0 lines=3',
      'cpp_target_phase=render_helper_method_timing owner=B name=end seconds=1.0 lines=4'
    ])
    const sharedSummary = runCase(tmpDir, 'shared', [sharedA, sharedB], 'shared-hotspots-moving-frontier', 'repeated_top_timings=class:Shared(2)')
    if (sharedSummary.repeatedFrontiers.length !== 0) fail('shared: expected no repeated frontier')

    const movingA = writeLog(tmpDir, 'moving-a.log', [
      'cpp_target_phase=render_helper_class_timing name=One seconds=5.0 lines=3',
      'cpp_target_phase=render_helper_method_timing owner=A name=end seconds=1.0 lines=4'
    ])
    const movingB = writeLog(tmpDir, 'moving-b.log', [
      'cpp_target_phase=render_helper_class_timing name=Two seconds=6.0 lines=3',
      'cpp_target_phase=render_helper_method_timing owner=B name=end seconds=1.0 lines=4'
    ])
    runCase(tmpDir, 'moving', [movingA, movingB], 'moving-frontier', 'repeated_frontiers=none')

    console.log('[ci:guards] OK: Cpp strict frontier summary fixtures pass')
  } finally {
    fs.rmSync(tmpDir, {recursive: true, force: true})
  }
}

main()
