#!/usr/bin/env node
/**
 * Measure upstream-suite compiler workloads for Full1 perf evidence.
 *
 * This adapter records one compiler-workload sample per strict Full1 suite for
 * upstream Haxe and stage0-free hxhx. The evaluator decides whether those
 * samples are fast/stable enough; this script only produces measured evidence.
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')
const { SUITES, listUniqueSuiteDependencies } = require('./upstream-suite-config')

const defaultSuites = ['misc', 'server', 'threads', 'optimization', 'display']
const cleanupFiles = []

process.on('exit', () => {
  for (const filePath of cleanupFiles) {
    try {
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath)
    } catch (_) {
      // Best-effort cleanup only; the original test failure should remain visible.
    }
  }
})

function fail(message, code = 2) {
  console.error(`[full1-suite-evidence] ERROR: ${message}`)
  process.exit(code)
}

function usage() {
  console.error(`Usage: node scripts/ci/full1-suite-evidence.js --json-out <evidence.json>

Options:
  --artifacts-dir <path>  Directory for per-suite logs
  --hxhx-bin <path>       Prebuilt hxhx binary (default: HXHX_BIN or suite runner build)
  --json-out <path>       Full1 perf evidence JSON output path
  --root <path>           Repository root (default: cwd)
  --suites <csv>          Suite IDs to measure (default: ${defaultSuites.join(',')})
  --upstream-dir <path>   Haxe upstream checkout (default: vendor/haxe)
`)
}

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    upstreamDir: '',
    artifactsDir: '.artifacts/full1/perf/suites',
    hxhxBin: process.env.HXHX_BIN || '',
    jsonOut: '',
    suites: defaultSuites.slice()
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--root') {
      i += 1
      out.root = argv[i] || ''
    } else if (arg === '--upstream-dir') {
      i += 1
      out.upstreamDir = argv[i] || ''
    } else if (arg === '--artifacts-dir') {
      i += 1
      out.artifactsDir = argv[i] || ''
    } else if (arg === '--hxhx-bin') {
      i += 1
      out.hxhxBin = argv[i] || ''
    } else if (arg === '--json-out') {
      i += 1
      out.jsonOut = argv[i] || ''
    } else if (arg === '--suites') {
      i += 1
      out.suites = String(argv[i] || '')
        .split(',')
        .map(suite => suite.trim().toLowerCase())
        .filter(Boolean)
    } else if (arg === '--help' || arg === '-h') {
      usage()
      process.exit(0)
    } else {
      fail(`unknown argument: ${arg}`)
    }
  }
  if (!out.root) fail('--root must not be empty')
  if (!out.jsonOut) fail('--json-out is required')
  if (out.suites.length === 0) fail('--suites must include at least one suite')
  for (const suite of out.suites) {
    if (!(suite in SUITES)) fail(`unsupported suite: ${suite}`)
  }
  out.root = path.resolve(out.root)
  out.upstreamDir = out.upstreamDir ? path.resolve(out.root, out.upstreamDir) : path.join(out.root, 'vendor/haxe')
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  out.hxhxBin = out.hxhxBin ? path.resolve(out.root, out.hxhxBin) : ''
  out.jsonOut = path.resolve(out.root, out.jsonOut)
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function writeLog(dir, name, result) {
  ensureDir(dir)
  fs.writeFileSync(path.join(dir, `${name}.stdout.log`), result.stdout || '', 'utf8')
  fs.writeFileSync(path.join(dir, `${name}.stderr.log`), result.stderr || '', 'utf8')
}

function listProcessRows() {
  const result = cp.spawnSync('ps', ['-eo', 'pid=,ppid=,rss='], {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 8
  })
  if (result.status !== 0) return []
  return String(result.stdout || '')
    .split(/\r?\n/)
    .map(line => {
      const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)$/)
      if (!match) return null
      return {
        pid: Number(match[1]),
        ppid: Number(match[2]),
        rssKb: Number(match[3])
      }
    })
    .filter(row => row && Number.isFinite(row.pid) && Number.isFinite(row.ppid) && Number.isFinite(row.rssKb))
}

function treeRssKb(rootPid) {
  const rows = listProcessRows()
  const childrenByParent = new Map()
  const rssByPid = new Map()
  for (const row of rows) {
    rssByPid.set(row.pid, row.rssKb)
    const children = childrenByParent.get(row.ppid) || []
    children.push(row.pid)
    childrenByParent.set(row.ppid, children)
  }

  let total = 0
  const seen = new Set()
  const stack = [rootPid]
  while (stack.length > 0) {
    const pid = stack.pop()
    if (seen.has(pid)) continue
    seen.add(pid)
    total += rssByPid.get(pid) || 0
    for (const child of childrenByParent.get(pid) || []) stack.push(child)
  }
  return total
}

function runMeasured(command, args, options) {
  return new Promise(resolve => {
    const started = process.hrtime.bigint()
    const child = cp.spawn(command, args, {
      cwd: options.cwd,
      env: options.env,
      stdio: ['ignore', 'pipe', 'pipe']
    })
    let stdout = ''
    let stderr = ''
    let peakRssKb = 0
    child.stdout.on('data', chunk => {
      stdout += chunk.toString('utf8')
    })
    child.stderr.on('data', chunk => {
      stderr += chunk.toString('utf8')
    })
    const poll = setInterval(() => {
      const rssKb = treeRssKb(child.pid)
      if (rssKb > peakRssKb) peakRssKb = rssKb
    }, 100)
    child.on('close', (status, signal) => {
      clearInterval(poll)
      const finalRssKb = treeRssKb(child.pid)
      if (finalRssKb > peakRssKb) peakRssKb = finalRssKb
      const ended = process.hrtime.bigint()
      resolve({
        status,
        signal,
        stdout,
        stderr,
        durationMs: Number((ended - started) / 1000000n),
        peakRssKb
      })
    })
    child.on('error', error => {
      clearInterval(poll)
      const ended = process.hrtime.bigint()
      resolve({
        status: -1,
        signal: '',
        stdout,
        stderr,
        error,
        durationMs: Number((ended - started) / 1000000n),
        peakRssKb
      })
    })
  })
}

function runSync(command, args, options) {
  return cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64
  })
}

function parseHaxelibPathLines(outputText) {
  return String(outputText || '')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line.length > 0)
}

function haxelibPathToHxmlLines(lines, lib) {
  const out = []
  for (const line of lines) {
    if (/^-lib\s+\S+\s+is missing\b/.test(line)) {
      fail(`haxelib path ${lib} reported missing library: ${line}`)
    }
    if (
      line.startsWith('-D ')
      || line.startsWith('--macro ')
      || line.startsWith('-cp ')
      || line.startsWith('--class-path ')
      || line.startsWith('-')
    ) {
      out.push(line)
      continue
    }
    out.push(`-cp ${line}`)
  }
  if (out.length === 0) fail(`haxelib path ${lib} produced no usable hxml lines`)
  return out
}

function writeTemporaryLibraryHxml(root, lib, lines) {
  const hxmlDir = path.join(root, 'haxe_libraries')
  const hxmlPath = path.join(hxmlDir, `${lib}.hxml`)
  if (fs.existsSync(hxmlPath)) return
  ensureDir(hxmlDir)
  fs.writeFileSync(hxmlPath, haxelibPathToHxmlLines(lines, lib).join('\n') + '\n', 'utf8')
  cleanupFiles.push(hxmlPath)
}

function writeRootLibraryHxmls(parsed, env) {
  const haxelib = env.HAXELIB_BIN || 'haxelib'
  for (const dep of listUniqueSuiteDependencies(parsed.suites)) {
    const result = runSync(haxelib, ['--always', 'path', dep.name], {
      cwd: parsed.root,
      env
    })
    writeLog(parsed.artifactsDir, `${dep.name}-path`, result)
    if (result.status !== 0) fail(`failed to resolve suite dependency path for ${dep.name} (exit=${result.status})`)
    writeTemporaryLibraryHxml(parsed.root, dep.name, parseHaxelibPathLines(result.stdout || ''))
  }
}

function prepareDependencies(parsed, env) {
  const repoPath = path.join(parsed.artifactsDir, 'haxelib_repo')
  const summaryPath = path.join(parsed.artifactsDir, 'haxelib_repo.summary.json')
  ensureDir(repoPath)
  const result = runSync(process.execPath, [
    'scripts/ci/prepare-suite-haxelib-deps.js',
    '--repo-path',
    repoPath,
    '--summary-path',
    summaryPath,
    '--suites',
    parsed.suites.join(',')
  ], {
    cwd: parsed.root,
    env: {
      ...env,
      HAXELIB_PATH: repoPath
    }
  })
  writeLog(parsed.artifactsDir, 'prepare-suite-haxelib-deps', result)
  if (result.status !== 0) fail(`failed to prepare suite haxelib dependencies (exit=${result.status})`)
  const preparedEnv = {
    ...env,
    HAXELIB_PATH: repoPath
  }
  writeRootLibraryHxmls(parsed, preparedEnv)
  return repoPath
}

async function measureUpstream(parsed, env, suite) {
  const suiteConfig = SUITES[suite]
  const suiteDir = path.join(parsed.root, suiteConfig.cwd)
  const hxmlPath = path.join(suiteDir, suiteConfig.entryHxml)
  if (!fs.existsSync(hxmlPath)) fail(`missing upstream suite hxml: ${hxmlPath}`)
  const result = await runMeasured('haxe', [suiteConfig.entryHxml], { cwd: suiteDir, env })
  writeLog(path.join(parsed.artifactsDir, `upstream-${suite}`), suiteConfig.entryHxml, result)
  return result
}

async function measureHxhx(parsed, env, suite) {
  const args = [
    'scripts/ci/run-upstream-suite.js',
    '--suite',
    suite,
    '--strict',
    '--artifacts-dir',
    path.join(parsed.artifactsDir, `hxhx-${suite}`)
  ]
  if (parsed.hxhxBin) {
    args.push('--hxhx-bin', parsed.hxhxBin)
  }
  const result = await runMeasured(process.execPath, args, { cwd: parsed.root, env })
  writeLog(path.join(parsed.artifactsDir, `hxhx-${suite}`), 'runner', result)
  return result
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2))
  if (!fs.existsSync(path.join(parsed.upstreamDir, 'tests'))) {
    fail(`upstream tests directory missing under: ${parsed.upstreamDir}`)
  }
  if (parsed.hxhxBin && !fs.existsSync(parsed.hxhxBin)) {
    fail(`provided hxhx binary does not exist: ${parsed.hxhxBin}`)
  }
  ensureDir(parsed.artifactsDir)
  ensureDir(path.dirname(parsed.jsonOut))

  const env = {
    ...process.env,
    HAXE_UPSTREAM_DIR: parsed.upstreamDir,
    HXHX_FORBID_STAGE0: '1'
  }
  delete env.HXHX_ALLOW_STAGE0
  if (parsed.hxhxBin) env.HXHX_BIN = parsed.hxhxBin
  env.HAXELIB_PATH = prepareDependencies(parsed, env)

  const upstreamWall = []
  const upstreamRss = []
  const hxhxWall = []
  const hxhxRss = []
  const suiteResults = []
  const workloadFailures = []

  for (const suite of parsed.suites) {
    const upstream = await measureUpstream(parsed, env, suite)
    const hxhx = await measureHxhx(parsed, env, suite)
    upstreamWall.push(upstream.durationMs)
    upstreamRss.push(upstream.peakRssKb)
    hxhxWall.push(hxhx.durationMs)
    hxhxRss.push(hxhx.peakRssKb)
    suiteResults.push({
      suite,
      upstream_haxe: {
        compile_wall_ms: upstream.durationMs,
        peak_rss_kb: upstream.peakRssKb,
        exit_code: upstream.status == null ? -1 : upstream.status
      },
      hxhx: {
        compile_wall_ms: hxhx.durationMs,
        peak_rss_kb: hxhx.peakRssKb,
        exit_code: hxhx.status == null ? -1 : hxhx.status
      }
    })
    if (upstream.status !== 0) {
      workloadFailures.push(`upstream_haxe suite ${suite} failed during measurement (exit=${upstream.status})`)
    }
    if (hxhx.status !== 0) {
      workloadFailures.push(`hxhx suite ${suite} failed during measurement (exit=${hxhx.status})`)
    }
  }

  const evidence = {
    schema: 'full1-perf-evidence.v1',
    haxeCompatibilityBaseline: '4.3.7',
    runner: {
      source: 'scripts/ci/full1-suite-evidence.js',
      suites: parsed.suites,
      samplesAreSuites: true,
      suiteResults
    },
    git: {
      sha: process.env.GITHUB_SHA || null,
      ref: process.env.GITHUB_REF || null,
      run_id: process.env.GITHUB_RUN_ID || null,
      run_attempt: process.env.GITHUB_RUN_ATTEMPT || null
    },
    workloads: [
      {
        id: 'full1-upstream-suite-compiler-workloads',
        failures: workloadFailures,
        samples: [
          {
            metric: 'compile_wall_ms',
            lane: 'upstream_haxe',
            values: upstreamWall
          },
          {
            metric: 'compile_wall_ms',
            lane: 'hxhx',
            values: hxhxWall
          },
          {
            metric: 'peak_rss_kb',
            lane: 'upstream_haxe',
            values: upstreamRss
          },
          {
            metric: 'peak_rss_kb',
            lane: 'hxhx',
            values: hxhxRss
          }
        ]
      }
    ]
  }
  fs.writeFileSync(parsed.jsonOut, JSON.stringify(evidence, null, 2) + '\n')
  console.log(`[full1-suite-evidence] evidence=${parsed.jsonOut}`)
}

main().catch(error => fail(error && error.stack ? error.stack : String(error), 1))
