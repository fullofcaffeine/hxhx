#!/usr/bin/env node
/**
 * run-embedding-subprocess-example.js
 *
 * Runnable embedding contract demo:
 * - compile a tiny program through `hxhx` as a subprocess;
 * - capture exit code/stdout/stderr;
 * - capture OCaml report artifact metadata;
 * - compile a failing program to capture deterministic diagnostics.
 */

const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const buildHxhxScript = path.join(root, 'scripts', 'hxhx', 'build-hxhx.sh')
const fixtureCp = path.join(root, 'examples', 'hxhx-embedding-subprocess', 'src')
const outRoot = path.resolve(process.env.HXHX_EMBED_EXAMPLE_OUT || path.join(root, '.tmp', 'embedding-subprocess-example'))
const successOutDir = path.join(outRoot, 'success')
const failureOutDir = path.join(outRoot, 'failure')
const successStdoutPath = path.join(outRoot, 'success.stdout.log')
const successStderrPath = path.join(outRoot, 'success.stderr.log')
const failureStdoutPath = path.join(outRoot, 'failure.stdout.log')
const failureStderrPath = path.join(outRoot, 'failure.stderr.log')
const resultPath = path.join(outRoot, 'embedding_subprocess_result.json')
const reportName = 'ocaml_portable_metalization_plan_report.json'
const passMarker = 'EMBEDDING_SUBPROCESS_EXAMPLE:PASS'

const hxhxBinCandidates = [
  path.join(root, 'packages', 'hxhx', 'bootstrap_work', '_build', 'default', 'out.exe'),
  path.join(root, 'packages', 'hxhx', 'bootstrap_work', '_build', 'default', 'out.bc'),
  path.join(root, 'packages', 'hxhx', 'out', '_build', 'default', 'out.exe'),
  path.join(root, 'packages', 'hxhx', 'out', '_build', 'default', 'out.bc'),
]

function fail(message) {
  console.error(`[embedding-subprocess-example] ERROR: ${message}`)
  process.exit(1)
}

function run(cmd, args, options = {}) {
  const result = cp.spawnSync(cmd, args, {
    cwd: root,
    encoding: 'utf8',
    env: { ...process.env, ...(options.env || {}) },
    maxBuffer: 20 * 1024 * 1024,
  })
  if (result.error) {
    fail(`${cmd} failed to start: ${result.error.message}`)
  }
  return {
    status: result.status == null ? 1 : result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
  }
}

function firstExistingHxhxBin() {
  for (const candidate of hxhxBinCandidates) {
    if (fs.existsSync(candidate)) {
      return candidate
    }
  }
  return null
}

function resolveHxhxBin() {
  const fromEnv = process.env.HXHX_BIN
  if (fromEnv && fs.existsSync(fromEnv)) {
    return path.resolve(fromEnv)
  }
  const existing = firstExistingHxhxBin()
  if (existing != null) {
    return path.resolve(existing)
  }

  const build = run('bash', [buildHxhxScript])
  if (build.status !== 0) {
    fail(`failed to build hxhx (exit ${build.status}).\n${build.stdout}${build.stderr}`)
  }
  const lines = build.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
  const maybePath = lines.length > 0 ? lines[lines.length - 1] : ''
  if (!maybePath || !fs.existsSync(maybePath)) {
    fail(`unable to resolve hxhx binary from ${buildHxhxScript}`)
  }
  return path.resolve(maybePath)
}

function ensureCleanDir(dir) {
  fs.rmSync(dir, { recursive: true, force: true })
  fs.mkdirSync(dir, { recursive: true })
}

function findDiagnosticSample(stdout, stderr) {
  const combined = `${stdout}\n${stderr}`.split(/\r?\n/)
  for (const line of combined) {
    const trimmed = line.trim()
    if (trimmed.length === 0) {
      continue
    }
    if (trimmed.indexOf('MissingMain') >= 0) {
      return trimmed
    }
    if (trimmed.toLowerCase().indexOf('error') >= 0) {
      return trimmed
    }
  }
  return '(no diagnostic line matched)'
}

function main() {
  if (!fs.existsSync(fixtureCp)) {
    fail(`missing fixture classpath: ${fixtureCp}`)
  }

  ensureCleanDir(outRoot)
  fs.mkdirSync(successOutDir, { recursive: true })
  fs.mkdirSync(failureOutDir, { recursive: true })

  const hxhxBin = resolveHxhxBin()

  const successArgs = [
    '--ocaml',
    '--hxhx-no-run',
    '--hxhx-out', successOutDir,
    '-cp', fixtureCp,
    '-main', 'Main',
    '-D', 'ocaml_profile=portable',
  ]

  const success = run(hxhxBin, successArgs, {
    env: { HXHX_FORBID_STAGE0: '1' },
  })
  fs.writeFileSync(successStdoutPath, success.stdout)
  fs.writeFileSync(successStderrPath, success.stderr)
  if (success.status !== 0) {
    fail(`successful compile unexpectedly failed (exit ${success.status}).`)
  }

  const reportPath = path.join(successOutDir, reportName)
  if (!fs.existsSync(reportPath)) {
    fail(`missing report artifact: ${reportPath}`)
  }
  const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))

  const failureArgs = [
    '--ocaml',
    '--hxhx-no-run',
    '--hxhx-out', failureOutDir,
    '-cp', fixtureCp,
    '-main', 'MissingMain',
    '-D', 'ocaml_profile=portable',
  ]
  const failure = run(hxhxBin, failureArgs, {
    env: { HXHX_FORBID_STAGE0: '1' },
  })
  fs.writeFileSync(failureStdoutPath, failure.stdout)
  fs.writeFileSync(failureStderrPath, failure.stderr)
  if (failure.status === 0) {
    fail('failing compile unexpectedly succeeded')
  }

  const output = {
    schemaVersion: 1,
    contractId: 'hxhx.embed.subprocess.v1',
    hxhxBin,
    fixtureClassPath: fixtureCp,
    successCompile: {
      command: [hxhxBin].concat(successArgs).join(' '),
      exitCode: success.status,
      stdoutPath: successStdoutPath,
      stderrPath: successStderrPath,
      reportPath,
      reportSummary: {
        schemaVersion: report.schemaVersion || null,
        profile: report.profile || null,
        plannerMode: report.plannerMode || null,
        totalRegions: report.summary && typeof report.summary.totalRegions === 'number'
          ? report.summary.totalRegions
          : null,
      },
    },
    failureCompile: {
      command: [hxhxBin].concat(failureArgs).join(' '),
      exitCode: failure.status,
      stdoutPath: failureStdoutPath,
      stderrPath: failureStderrPath,
      diagnosticSample: findDiagnosticSample(failure.stdout, failure.stderr),
    },
  }

  fs.writeFileSync(resultPath, `${JSON.stringify(output, null, 2)}\n`)
  console.log(`embedding_result_json=${resultPath}`)
  console.log(passMarker)
}

main()
