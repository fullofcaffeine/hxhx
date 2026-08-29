#!/usr/bin/env node
const fs = require('fs')
const path = require('path')
const cp = require('child_process')
const crypto = require('crypto')
const { measureIterationScenario } = require('./reflaxe-ocaml-iteration-perf')

const {
  cleanupPerformanceContext,
  createPerformanceContext,
  environmentSummary,
  provenanceSummary,
  sanitizeText,
  scenarioDirectory,
  verifyEvidenceSanitized
} = require('./reflaxe-ocaml-perf-platform')

const repoRoot = process.cwd()
const baselinePath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json')
const artifactsDir = path.resolve(process.env.RO_PERF_ARTIFACTS || path.join(repoRoot, '.artifacts/reflaxe-ocaml/perf'))
const mode = process.env.RO_PERF_MODE || 'reference-gate'

function fail(message) {
  throw new Error(message)
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 1 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2)
}

function stats(values) {
  if (!values.length) {
    return { samplesMs: [], reps: 0, avgMs: 0, bestMs: 0, medianMs: 0, worstMs: 0 }
  }
  const total = values.reduce((sum, value) => sum + value, 0)
  return {
    samplesMs: [...values],
    reps: values.length,
    avgMs: Math.round(total / values.length),
    bestMs: Math.min(...values),
    medianMs: median(values),
    worstMs: Math.max(...values)
  }
}

function run(command, args, options) {
  const started = process.hrtime.bigint()
  const result = cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
    shell: false
  })
  const ended = process.hrtime.bigint()
  const durationMs = Number((ended - started) / 1000000n)
  return {
    status: result.status == null ? 1 : result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    durationMs
  }
}

function normalized(text) {
  return String(text).replace(/\r\n/g, '\n').trim()
}

function sha256Text(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function expectedExampleStdout(exampleDir) {
  const expectedPath = path.join(exampleDir, 'expected.stdout')
  if (!fs.existsSync(expectedPath)) {
    fail(`performance example is missing expected.stdout: ${expectedPath}`)
  }
  return normalized(fs.readFileSync(expectedPath, 'utf8'))
}

function verifyBuiltExample(scenario, exampleDir, logDir, context) {
  const expectedStdout = expectedExampleStdout(exampleDir)
  const executable = path.resolve(exampleDir, scenario.executableRelativePath)
  if (!fs.existsSync(executable)) {
    return {
      passed: false,
      runStatus: 1,
      stdoutMatches: false,
      expectedStdoutSha256: sha256Text(expectedStdout),
      actualStdoutSha256: null,
      failure: 'native executable was not produced'
    }
  }
  const result = run(executable, [], {
    cwd: exampleDir,
    env: { ...context.env, HX_TEST_ENV: 'ok' }
  })
  writeLogs(logDir, 'verification-run', result, context)
  fs.writeFileSync(path.join(logDir, 'expected.stdout.log'), expectedStdout + '\n')
  const actualStdout = normalized(result.stdout)
  const stdoutMatches = actualStdout === expectedStdout
  return {
    passed: result.status === 0 && stdoutMatches,
    runStatus: result.status,
    stdoutMatches,
    expectedStdoutSha256: sha256Text(expectedStdout),
    actualStdoutSha256: sha256Text(actualStdout),
    failure: result.status === 0 && stdoutMatches ? null : 'native executable failed or stdout did not match expected.stdout'
  }
}

function rmOutputDir(exampleDir, outDirName) {
  fs.rmSync(path.join(exampleDir, outDirName), { recursive: true, force: true })
}

function collectBuildArtifacts(exampleDir, outDirName, executableRelativePath) {
  const outDir = path.join(exampleDir, outDirName)
  const exePath = path.join(exampleDir, executableRelativePath)
  const generatedMlFiles = []
  let generatedMlBytes = 0

  if (fs.existsSync(outDir)) {
    const stack = [outDir]
    while (stack.length) {
      const current = stack.pop()
      const entries = fs.readdirSync(current, { withFileTypes: true })
      for (const entry of entries) {
        const fullPath = path.join(current, entry.name)
        if (entry.isDirectory()) {
          stack.push(fullPath)
          continue
        }
        if (entry.name.endsWith('.ml') || entry.name.endsWith('.mli')) {
          generatedMlFiles.push(path.relative(exampleDir, fullPath))
          generatedMlBytes += fs.statSync(fullPath).size
        }
      }
    }
  }

  return {
    generatedMlFileCount: generatedMlFiles.length,
    generatedMlBytes,
    executableBytes: fs.existsSync(exePath) ? fs.statSync(exePath).size : 0,
    executableRelativePath
  }
}

function computeBenchValue(n) {
  function clampMod(v) {
    const r = v % 1000003
    return r < 0 ? r + 1000003 : r
  }

  let acc = 0
  let alt = 1
  let wobble = 17
  for (let i = 0; i < n; i += 1) {
    const c = ((i * 13 + 5) % 97) + 1
    acc = clampMod(acc + (c * (i + 3)))
    alt = clampMod((alt * 7) + (i % 101) + c)
    wobble = clampMod((wobble * 11) + (c % 19) + (i % 7))
    if ((i % 3) === 0) {
      acc = clampMod(acc + alt + wobble)
    } else {
      acc = clampMod(acc - alt + wobble)
    }
  }

  return clampMod(acc + alt + wobble)
}

function expectedBenchStdout(iterations) {
  return `bench_iters=${iterations}\nbench_result=${computeBenchValue(iterations)}`
}

function compareMeasured(metricName, measuredValue, baselineMetric) {
  if (!baselineMetric || typeof baselineMetric.value !== 'number') {
    return { ok: true, reason: 'no baseline configured' }
  }
  const allowedRegressionPct = typeof baselineMetric.maxRegressionPct === 'number' ? baselineMetric.maxRegressionPct : 0
  const maxAllowed = Math.round(baselineMetric.value * (1 + (allowedRegressionPct / 100)))
  const ok = measuredValue <= maxAllowed
  return {
    ok,
    baseline: baselineMetric.value,
    maxAllowed,
    allowedRegressionPct,
    measured: measuredValue,
    reason: ok
      ? `${metricName} within allowed regression window`
      : `${metricName}=${measuredValue} exceeds maxAllowed=${maxAllowed}`
  }
}

function compareMinimum(metricName, measuredValue, baselineMetric) {
  if (!baselineMetric || typeof baselineMetric.value !== 'number') {
    return { ok: true, reason: 'no baseline configured' }
  }
  const allowedDropPct = typeof baselineMetric.maxDropPct === 'number' ? baselineMetric.maxDropPct : 0
  const minAllowed = Math.round(baselineMetric.value * (1 - (allowedDropPct / 100)))
  const ok = measuredValue >= minAllowed
  return {
    ok,
    baseline: baselineMetric.value,
    minAllowed,
    allowedDropPct,
    measured: measuredValue,
    reason: ok
      ? `${metricName} within allowed drop window`
      : `${metricName}=${measuredValue} is below minAllowed=${minAllowed}`
  }
}

function writeLogs(logDir, prefix, result, context) {
  fs.writeFileSync(path.join(logDir, `${prefix}.stdout.log`), sanitizeText(result.stdout, context))
  fs.writeFileSync(path.join(logDir, `${prefix}.stderr.log`), sanitizeText(result.stderr, context))
}

function measureBuildScenario(scenario, baseline, summary, context) {
  const exampleDir = scenarioDirectory(scenario, context)
  const logDir = path.join(artifactsDir, scenario.id)
  ensureDir(logDir)

  const durations = []
  let lastResult = null
  for (let rep = 0; rep < scenario.buildReps; rep += 1) {
    rmOutputDir(exampleDir, scenario.outDir)
    lastResult = run('haxe', scenario.compileArgs, {
      cwd: exampleDir,
      env: context.env
    })
    durations.push(lastResult.durationMs)
    writeLogs(logDir, `build-rep-${rep + 1}`, lastResult, context)
    if (lastResult.status !== 0) {
      break
    }
  }

  if (!lastResult || lastResult.status !== 0) {
    summary.scenarios.push({
      id: scenario.id,
      kind: scenario.kind,
      passed: false,
      compileStatus: lastResult ? lastResult.status : 1,
      failure: 'compile failed'
    })
    return false
  }

  const artifactStats = collectBuildArtifacts(exampleDir, scenario.outDir, scenario.executableRelativePath)
  const verification = verifyBuiltExample(scenario, exampleDir, logDir, context)
  const measured = {
    build: stats(durations),
    generatedMlFileCount: artifactStats.generatedMlFileCount,
    generatedMlBytes: artifactStats.generatedMlBytes,
    executableBytes: artifactStats.executableBytes
  }

  const comparisons = {
    buildMedianMs: compareMeasured('buildMedianMs', measured.build.medianMs, baseline.thresholds && baseline.thresholds.buildMedianMs),
    executableBytes: compareMeasured('executableBytes', measured.executableBytes, baseline.thresholds && baseline.thresholds.executableBytes),
    generatedMlBytes: compareMeasured('generatedMlBytes', measured.generatedMlBytes, baseline.thresholds && baseline.thresholds.generatedMlBytes)
  }

  const referenceComparisonsPassed = Object.values(comparisons).every(entry => entry.ok)
  const passed = verification.passed && (!context.enforceReferenceThresholds || referenceComparisonsPassed)
  summary.scenarios.push({
    id: scenario.id,
    kind: scenario.kind,
    title: scenario.title,
    exampleDir: scenario.exampleDir,
    compileStatus: lastResult.status,
    verification,
    measured,
    comparisons,
    referenceComparisonsEnforced: context.enforceReferenceThresholds,
    passed
  })
  return passed
}

function measureBenchScenario(scenario, baseline, summary, context) {
  const exampleDir = scenarioDirectory(scenario, context)
  const logDir = path.join(artifactsDir, scenario.id)
  ensureDir(logDir)
  const expectedStdout = expectedBenchStdout(scenario.iterations)

  const buildDurations = []
  let lastBuild = null
  for (let rep = 0; rep < scenario.buildReps; rep += 1) {
    rmOutputDir(exampleDir, scenario.outDir)
    lastBuild = run('haxe', scenario.compileArgs, {
      cwd: exampleDir,
      env: context.env
    })
    buildDurations.push(lastBuild.durationMs)
    writeLogs(logDir, `build-rep-${rep + 1}`, lastBuild, context)
    if (lastBuild.status !== 0) {
      break
    }
  }

  if (!lastBuild || lastBuild.status !== 0) {
    summary.scenarios.push({
      id: scenario.id,
      kind: scenario.kind,
      passed: false,
      compileStatus: lastBuild ? lastBuild.status : 1,
      failure: 'compile failed'
    })
    return false
  }

  const runDurations = []
  let lastRun = null
  for (let rep = 0; rep < scenario.runReps; rep += 1) {
    lastRun = run(scenario.runArgv[0], scenario.runArgv.slice(1), {
      cwd: exampleDir,
      env: { ...context.env, HXHX_BENCH_ITERS: String(scenario.iterations) }
    })
    runDurations.push(lastRun.durationMs)
    writeLogs(logDir, `run-rep-${rep + 1}`, lastRun, context)
    if (lastRun.status !== 0 || normalized(lastRun.stdout) !== normalized(expectedStdout)) {
      break
    }
  }

  if (!lastRun || lastRun.status !== 0 || normalized(lastRun.stdout) !== normalized(expectedStdout)) {
    summary.scenarios.push({
      id: scenario.id,
      kind: scenario.kind,
      passed: false,
      compileStatus: lastBuild.status,
      runStatus: lastRun ? lastRun.status : 1,
      stdoutMatches: !!lastRun && normalized(lastRun.stdout) === normalized(expectedStdout),
      failure: 'run failed or output mismatch'
    })
    fs.writeFileSync(path.join(logDir, 'expected.stdout.log'), expectedStdout + '\n')
    return false
  }

  const artifactStats = collectBuildArtifacts(exampleDir, scenario.outDir, scenario.executableRelativePath)
  const measured = {
    build: stats(buildDurations),
    run: stats(runDurations),
    generatedMlFileCount: artifactStats.generatedMlFileCount,
    generatedMlBytes: artifactStats.generatedMlBytes,
    executableBytes: artifactStats.executableBytes
  }

  const comparisons = {
    buildMedianMs: compareMeasured('buildMedianMs', measured.build.medianMs, baseline.thresholds && baseline.thresholds.buildMedianMs),
    runMedianMs: compareMeasured('runMedianMs', measured.run.medianMs, baseline.thresholds && baseline.thresholds.runMedianMs),
    executableBytes: compareMeasured('executableBytes', measured.executableBytes, baseline.thresholds && baseline.thresholds.executableBytes),
    generatedMlBytes: compareMeasured('generatedMlBytes', measured.generatedMlBytes, baseline.thresholds && baseline.thresholds.generatedMlBytes)
  }

  const referenceComparisonsPassed = Object.values(comparisons).every(entry => entry.ok)
  const passed = !context.enforceReferenceThresholds || referenceComparisonsPassed
  summary.scenarios.push({
    id: scenario.id,
    kind: scenario.kind,
    title: scenario.title,
    exampleDir: scenario.exampleDir,
    compileStatus: lastBuild.status,
    runStatus: lastRun.status,
    verification: {
      passed: true,
      stdoutMatches: true,
      expectedStdoutSha256: sha256Text(normalized(expectedStdout)),
      actualStdoutSha256: sha256Text(normalized(lastRun.stdout))
    },
    measured,
    comparisons,
    referenceComparisonsEnforced: context.enforceReferenceThresholds,
    passed
  })
  return passed
}

function main() {
  const baseline = readJson(baselinePath)
  if (baseline.marker !== 'RO_TARGET_PERF_CREDIBLE:PASS') {
    fail(`unexpected baseline marker ${baseline.marker}`)
  }
  const context = createPerformanceContext({
    repoRoot,
    artifactsDir,
    mode,
    environmentFile: process.env.RO_PERF_ENV_FILE,
    artifactManifest: process.env.RO_PERF_ARTIFACT_MANIFEST,
    packageInstallSummary: process.env.RO_PERF_PACKAGE_INSTALL_SUMMARY,
    workRoot: process.env.RO_PERF_WORK_ROOT
  })
  fs.rmSync(context.artifactsDir, { recursive: true, force: true })
  ensureDir(context.artifactsDir)

  try {
    const passMarker = mode === 'platform-report'
      ? 'RO_TARGET_PERF_PLATFORM:PASS'
      : baseline.marker
    const failMarker = mode === 'platform-report'
      ? 'RO_TARGET_PERF_PLATFORM:FAIL'
      : 'RO_TARGET_PERF_CREDIBLE:FAIL'
    const summary = {
      schemaVersion: 2,
      marker: failMarker,
      mode,
      generatedAt: new Date().toISOString(),
      method: {
        id: mode === 'platform-report' ? 'installed-package-platform-v2' : 'local-reference-gate-v3',
        durationUnit: 'milliseconds',
        rawSamplesRetained: true,
        sampleOrderPreserved: true,
        outputDirectoryRemovedBeforeEachBuild: true,
        sharedToolchainCachesMayRemainWarm: true,
        runtimeVerificationExcludedFromBuildTiming: true,
        iterationStateOrder: ['cold-output', 'warm-unchanged', 'one-file-change'],
        iterationWarmupCycles: baseline.iterationScenario.warmupCycles,
        iterationMeasuredCycles: baseline.iterationScenario.measuredCycles,
        iterationThresholdMode: 'report-only-until-stable-hosted-trend',
        crossHostAbsoluteComparisonAllowed: false,
        referenceThresholdsEnforced: context.enforceReferenceThresholds
      },
      referenceBaseline: {
        path: path.relative(repoRoot, baselinePath),
        lastAudited: baseline.lastAudited,
        host: baseline.baselineHost,
        comparisonsAreInformational: !context.enforceReferenceThresholds
      },
      environment: environmentSummary(context),
      provenance: provenanceSummary(context),
      evidence: {
        machineLocalPathsRedacted: true
      },
      scenarios: []
    }

    let allOk = true
    for (const scenario of baseline.scenarios) {
      const passed = scenario.kind === 'build_native'
        ? measureBuildScenario(scenario, scenario, summary, context)
        : measureBenchScenario(scenario, scenario, summary, context)
      if (!passed) {
        allOk = false
      }
    }

    summary.iteration = measureIterationScenario(baseline.iterationScenario, context, stats, context.artifactsDir)
    if (!summary.iteration.passed) {
      allOk = false
    }

    const portable = summary.scenarios.find(entry => entry.id === 'ro-perf-05')
    const metal = summary.scenarios.find(entry => entry.id === 'ro-perf-06')
    if (portable && metal && portable.measured && metal.measured
      && portable.measured.run.medianMs > 0 && portable.measured.build.medianMs > 0
      && metal.measured.run.medianMs > 0 && metal.measured.build.medianMs > 0) {
      const metalVsPortable = {
        runMedianPctOfPortable: Math.round((metal.measured.run.medianMs / portable.measured.run.medianMs) * 100),
        buildMedianPctOfPortable: Math.round((metal.measured.build.medianMs / portable.measured.build.medianMs) * 100)
      }
      summary.profileComparison = metalVsPortable
      const profileThresholds = baseline.profileComparisonThresholds || {}
      const runCheck = compareMeasured(
        'metalRunVsPortablePct',
        metalVsPortable.runMedianPctOfPortable,
        profileThresholds.runMedianPctOfPortable
          ? { value: profileThresholds.runMedianPctOfPortable.value, maxRegressionPct: profileThresholds.runMedianPctOfPortable.maxRegressionPct }
          : null
      )
      const buildCheck = compareMeasured(
        'metalBuildVsPortablePct',
        metalVsPortable.buildMedianPctOfPortable,
        profileThresholds.buildMedianPctOfPortable
          ? { value: profileThresholds.buildMedianPctOfPortable.value, maxRegressionPct: profileThresholds.buildMedianPctOfPortable.maxRegressionPct }
          : null
      )
      summary.profileComparisonChecks = { runCheck, buildCheck }
      if (context.enforceReferenceThresholds && (!runCheck.ok || !buildCheck.ok)) {
        allOk = false
      }
    } else {
      summary.profileComparisonError = 'portable and metal measurements must both have positive medians'
      allOk = false
    }

    summary.marker = allOk ? passMarker : failMarker
    const summaryPath = path.join(context.artifactsDir, 'summary.json')
    fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2) + '\n')
    verifyEvidenceSanitized(context)
    console.log('[reflaxe-ocaml-perf] summary=summary.json')
    console.log(summary.marker)
    return allOk
  } finally {
    cleanupPerformanceContext(context)
  }
}

if (require.main === module) {
  try {
    process.exitCode = main() ? 0 : 1
  } catch (error) {
    console.error(`[reflaxe-ocaml-perf] ERROR: ${error instanceof Error ? error.message : String(error)}`)
    process.exitCode = 1
  }
}

module.exports = { stats }
