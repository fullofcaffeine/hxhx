#!/usr/bin/env node
const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const repoRoot = process.cwd()
const manifestPath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.json')
const artifactsDir = path.join(repoRoot, '.artifacts/reflaxe-ocaml/haxe-matrix')

function fail(message) {
  console.error(`[reflaxe-ocaml-haxe-matrix] ERROR: ${message}`)
  process.exit(1)
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function run(command, args, options) {
  const result = cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    shell: false
  })
  return {
    status: result.status == null ? 1 : result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || ''
  }
}

function normalized(text) {
  return String(text).replace(/\r\n/g, '\n').trim()
}

function main() {
  const manifest = readJson(manifestPath)
  if (manifest.haxeCompatibilityBaseline !== '4.3.7') {
    fail(`expected Haxe 4.3.7 baseline, received ${manifest.haxeCompatibilityBaseline}`)
  }

  ensureDir(artifactsDir)

  const summary = {
    baseline: manifest.haxeCompatibilityBaseline,
    marker: 'RO_HAXE_4_3_7_MATRIX:FAIL',
    runner: manifest.runner,
    workloads: []
  }

  let allOk = true

  for (const workload of manifest.workloads) {
    const exampleDir = path.join(repoRoot, workload.exampleDir)
    const outDir = path.join(exampleDir, 'out')
    const expectedStdoutPath = path.join(exampleDir, workload.expectedStdoutFile)
    const workloadLogDir = path.join(artifactsDir, workload.name)
    ensureDir(workloadLogDir)
    fs.rmSync(outDir, { recursive: true, force: true })

    const compile = run('haxe', workload.compileArgs, {
      cwd: exampleDir,
      env: { ...process.env }
    })
    fs.writeFileSync(path.join(workloadLogDir, 'compile.stdout.log'), compile.stdout)
    fs.writeFileSync(path.join(workloadLogDir, 'compile.stderr.log'), compile.stderr)

    let runResult = { status: 1, stdout: '', stderr: 'skipped because compile failed' }
    let stdoutMatches = false
    if (compile.status === 0) {
      runResult = run(workload.run.argv[0], workload.run.argv.slice(1), {
        cwd: path.join(exampleDir, workload.run.cwd),
        env: { ...process.env, ...(workload.run.env || {}) }
      })
      fs.writeFileSync(path.join(workloadLogDir, 'run.stdout.log'), runResult.stdout)
      fs.writeFileSync(path.join(workloadLogDir, 'run.stderr.log'), runResult.stderr)
      const expectedStdout = fs.readFileSync(expectedStdoutPath, 'utf8')
      stdoutMatches = normalized(runResult.stdout) === normalized(expectedStdout)
      if (!stdoutMatches) {
        fs.writeFileSync(path.join(workloadLogDir, 'expected.stdout.log'), expectedStdout)
      }
    } else {
      fs.writeFileSync(path.join(workloadLogDir, 'run.stdout.log'), '')
      fs.writeFileSync(path.join(workloadLogDir, 'run.stderr.log'), runResult.stderr)
    }

    const passed = compile.status === 0 && runResult.status === 0 && stdoutMatches
    if (!passed) {
      allOk = false
    }

    summary.workloads.push({
      id: workload.id,
      name: workload.name,
      exampleDir: workload.exampleDir,
      compileStatus: compile.status,
      runStatus: runResult.status,
      stdoutMatches,
      passed
    })
  }

  summary.marker = allOk ? manifest.marker : 'RO_HAXE_4_3_7_MATRIX:FAIL'
  const summaryPath = path.join(artifactsDir, 'summary.json')
  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2) + '\n')
  console.log(`[reflaxe-ocaml-haxe-matrix] summary=${summaryPath}`)
  console.log(summary.marker)
  process.exit(allOk ? 0 : 1)
}

main()
