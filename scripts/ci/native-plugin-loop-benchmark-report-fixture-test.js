#!/usr/bin/env node

/**
 * Synthetic contract tests for native plugin-loop timing reports. These prove
 * report validation only; they are not plugin-build or performance evidence.
 */

const childProcess = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = process.cwd()
const validator = path.join(repoRoot, 'scripts/ci/native-plugin-loop-benchmark-report.js')
const runner = path.join(repoRoot, 'scripts/hxhx/bench-native-plugin-loop.sh')
const {
  buildComparison,
  passMarker,
  routeDefinitions,
  routeOrder,
  schema,
  summarizeRuns
} = require(validator)

const digest = 'a'.repeat(64)
const artifactDigest = 'b'.repeat(64)
const commit = '0123456789abcdef0123456789abcdef01234567'

function fail(message) {
  console.error(`[native-plugin-loop-benchmark-report-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function validReport() {
  const runs = [
    {
      route: 'upstream-to-hxhx',
      rep: 1,
      order: 1,
      elapsed_ms: 1000,
      proof: {
        summary_path: 'proofs/sample.1.upstream-to-hxhx/full1-plugin-upstream-to-hxhx.summary.json',
        summary_sha256: digest,
        marker: routeDefinitions['upstream-to-hxhx'].marker,
        candidate_sha: commit,
        plugin_artifact_sha256: artifactDigest
      }
    },
    {
      route: 'hxhx-to-hxhx',
      rep: 1,
      order: 2,
      elapsed_ms: 800,
      proof: {
        summary_path: 'proofs/sample.1.hxhx-to-hxhx/full1-plugin-hxhx-to-hxhx.summary.json',
        summary_sha256: digest,
        marker: routeDefinitions['hxhx-to-hxhx'].marker,
        candidate_sha: commit,
        plugin_artifact_sha256: artifactDigest
      }
    },
    {
      route: 'hxhx-to-hxhx',
      rep: 2,
      order: 1,
      elapsed_ms: 900,
      proof: {
        summary_path: 'proofs/sample.2.hxhx-to-hxhx/full1-plugin-hxhx-to-hxhx.summary.json',
        summary_sha256: digest,
        marker: routeDefinitions['hxhx-to-hxhx'].marker,
        candidate_sha: commit,
        plugin_artifact_sha256: artifactDigest
      }
    },
    {
      route: 'upstream-to-hxhx',
      rep: 2,
      order: 2,
      elapsed_ms: 1200,
      proof: {
        summary_path: 'proofs/sample.2.upstream-to-hxhx/full1-plugin-upstream-to-hxhx.summary.json',
        summary_sha256: digest,
        marker: routeDefinitions['upstream-to-hxhx'].marker,
        candidate_sha: commit,
        plugin_artifact_sha256: artifactDigest
      }
    }
  ]
  const summaries = summarizeRuns(runs)
  return {
    schema,
    artifact_kind: 'native-plugin-author-loop',
    evidence_level: 'diagnostic-report-only',
    marker: passMarker,
    recorded_at: '2026-07-14T00:00:00.000Z',
    git: {
      commit,
      tracked_source_clean_at_start: true,
      tracked_source_clean_at_end: true
    },
    environment: {
      os: 'Linux',
      architecture: 'x64',
      cpu_model: 'Fixture CPU',
      node_version: 'v20.0.0',
      haxe_path: 'haxe',
      haxe_version: '4.3.7',
      ocamlc_version: '5.2.1',
      ocamlopt_version: '5.2.1',
      dune_version: '3.15.3',
      hxhx_artifact_kind: 'native',
      hxhx_artifact_path: '.tmp/hxhx-bootstrap-build.fixture/_build/default/out.exe',
      hxhx_artifact_commit: commit,
      hxhx_artifact_sha256: digest
    },
    config: {
      reps: 2,
      warmups: 1,
      route_order: routeOrder
    },
    measurement: {
      command: 'npm run hxhx:bench:native-plugin-loop',
      sample_scope: 'fresh plugin emit, Dune plugin build, hxhx plugin load, sample compile, and sample runtime',
      preparation_scope: 'native hxhx executable preparation is timed separately and excluded from route samples',
      warmup_rule: '1 unrecorded correctness warmup run per route using fresh proof directories',
      state_rule: 'every recorded route sample uses a new temporary proof workspace and must emit a passing Full1 proof summary',
      route_definitions: JSON.parse(JSON.stringify(routeDefinitions))
    },
    hxhx_preparation: {
      provided_by_caller: false,
      elapsed_ms: 15000,
      command: 'HXHX_FORBID_STAGE0=1 HXHX_BOOTSTRAP_PREFER_NATIVE=1 HXHX_STAGE0_OCAML_BUILD=native bash scripts/hxhx/build-hxhx.sh'
    },
    runs,
    summaries,
    comparison: buildComparison(summaries)
  }
}

function materializeProofSummaries(report, tmpDir) {
  for (const run of report.runs) {
    const summaryPath = path.join(tmpDir, run.proof.summary_path)
    const artifactPath = path.join(path.dirname(summaryPath), 'verified-plugin-artifact.cmxs')
    fs.mkdirSync(path.dirname(summaryPath), { recursive: true })
    fs.writeFileSync(artifactPath, `fixture plugin ${run.route} ${run.rep}\n`)
    run.proof.plugin_artifact_sha256 = crypto.createHash('sha256').update(fs.readFileSync(artifactPath)).digest('hex')
    const summary = {
      schema: 'full1-plugin-proof.v1',
      synthetic: false,
      route: run.route,
      candidateSha: report.git.commit,
      marker: routeDefinitions[run.route].marker,
      result: routeDefinitions[run.route].marker,
      plugin: {
        artifactSha256: run.proof.plugin_artifact_sha256,
        evidenceArtifact: 'verified-plugin-artifact.cmxs'
      },
      sampleCompile: {
        selectedImpl: 'provider/js-native-wrapper',
        runtimeStdout: 'sum=6'
      },
      ...(run.route === 'hxhx-to-hxhx'
        ? { pluginCompiler: { kind: 'hxhx-stage3', stage0Forbidden: true } }
        : { hostCompiler: { kind: 'upstream-haxe' } })
    }
    fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`)
    run.proof.summary_sha256 = crypto.createHash('sha256').update(fs.readFileSync(summaryPath)).digest('hex')
  }
}

function runValidator(report, expectedStatus, label, tmpDir, options = {}) {
  materializeProofSummaries(report, tmpDir)
  const reportPath = path.join(tmpDir, `${label}.json`)
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
  const firstProof = path.join(tmpDir, report.runs[0]?.proof?.summary_path || '')
  const firstArtifact = path.join(path.dirname(firstProof), 'verified-plugin-artifact.cmxs')
  if (options.tamperProof && fs.existsSync(firstProof)) fs.appendFileSync(firstProof, 'tampered\n')
  if (options.removeProof && fs.existsSync(firstProof)) fs.rmSync(firstProof)
  if (options.tamperArtifact && fs.existsSync(firstArtifact)) fs.appendFileSync(firstArtifact, 'tampered\n')
  if (options.removeArtifact && fs.existsSync(firstArtifact)) fs.rmSync(firstArtifact)
  const result = childProcess.spawnSync(process.execPath, [validator, 'validate', '--report', reportPath], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== expectedStatus) {
    fail(`${label}: expected status ${expectedStatus}, received ${result.status}\n${result.stdout}\n${result.stderr}`)
  }
  if (expectedStatus === 0 && !result.stdout.includes(passMarker)) {
    fail(`${label}: valid fixture did not emit ${passMarker}`)
  }
}

function main() {
  const runnerSource = fs.readFileSync(runner, 'utf8')
  for (const token of [
    'run-full1-plugin-upstream-to-hxhx-proof.sh',
    'run-full1-plugin-hxhx-to-hxhx-proof.sh',
    'HXHX_FORBID_STAGE0=1',
    'HXHX_BOOTSTRAP_PREFER_NATIVE=1',
    'HXHX_STAGE0_OCAML_BUILD=native',
    'FULL1_PLUGIN_HXHX_BIN',
    'FULL1_PLUGIN_UPSTREAM_HXHX_BIN'
  ]) {
    if (!runnerSource.includes(token)) fail(`runner is missing required real-loop token: ${token}`)
  }
  if (runnerSource.includes('MIN_SPEEDUP') || runnerSource.includes('minimum speedup')) {
    fail('plugin-loop benchmark must remain report-only until repeated evidence supports a threshold')
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-native-plugin-loop-report-fixtures-'))
  try {
    runValidator(validReport(), 0, 'valid', tmpDir)
    const cases = [
      ['bad-schema', report => { report.schema = 'legacy' }],
      ['missing-recorded-at', report => { delete report.recorded_at }],
      ['missing-cpu', report => { delete report.environment.cpu_model }],
      ['bytecode-artifact', report => { report.environment.hxhx_artifact_kind = 'bytecode' }],
      ['absolute-artifact-path', report => { report.environment.hxhx_artifact_path = '/tmp/out.exe' }],
      ['bad-artifact-digest', report => { report.environment.hxhx_artifact_sha256 = 'bad' }],
      ['cross-commit-hxhx', report => { report.environment.hxhx_artifact_commit = 'f'.repeat(40) }],
      ['missing-run', report => { report.runs.pop() }],
      ['duplicate-route-rep', report => { report.runs[3].rep = 1 }],
      ['biased-route-order', report => { report.runs[0].order = 2 }],
      ['wrong-route-order-description', report => { report.config.route_order = 'upstream always first' }],
      ['summary-mismatch', report => { report.summaries[0].elapsed_ms.median = 1 }],
      ['comparison-mismatch', report => { report.comparison.hxhx_over_upstream = 99 }],
      ['cross-commit-proof', report => { report.runs[0].proof.candidate_sha = 'f'.repeat(40) }],
      ['wrong-route-marker', report => { report.runs[0].proof.marker = routeDefinitions['hxhx-to-hxhx'].marker }],
      ['synthetic-route-contract', report => { report.measurement.route_definitions['hxhx-to-hxhx'].label = 'fixture' }],
      ['negative-preparation', report => { report.hxhx_preparation.elapsed_ms = -1 }],
      ['release-looking-evidence', report => { report.evidence_level = 'release' }]
    ]
    for (const [label, mutate] of cases) {
      const report = validReport()
      mutate(report)
      runValidator(report, 1, label, tmpDir)
    }
    runValidator(validReport(), 1, 'tampered-proof-summary', tmpDir, { tamperProof: true })
    runValidator(validReport(), 1, 'missing-proof-summary', tmpDir, { removeProof: true })
    runValidator(validReport(), 1, 'tampered-plugin-artifact', tmpDir, { tamperArtifact: true })
    runValidator(validReport(), 1, 'missing-plugin-artifact', tmpDir, { removeArtifact: true })
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
  console.log('[ci:guards] OK: native plugin-loop benchmark report fixtures pass')
}

main()
