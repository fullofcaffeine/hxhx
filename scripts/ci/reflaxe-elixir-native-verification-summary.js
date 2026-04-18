#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

function readEnvFile(file) {
  const out = {}
  if (!fs.existsSync(file)) return out
  const text = fs.readFileSync(file, 'utf8')
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq === -1) continue
    out[line.slice(0, eq)] = line.slice(eq + 1)
  }
  return out
}

function parseArgs(argv) {
  const out = {
    artifactDir: '',
    jsonOut: '',
    lanes: '',
    sourceRepo: '',
    sourceCommit: '',
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--artifact-dir') out.artifactDir = argv[++i] || ''
    else if (arg === '--json-out') out.jsonOut = argv[++i] || ''
    else if (arg === '--lanes') out.lanes = argv[++i] || ''
    else if (arg === '--source-repo') out.sourceRepo = argv[++i] || ''
    else if (arg === '--source-commit') out.sourceCommit = argv[++i] || ''
    else {
      console.error(`unknown argument: ${arg}`)
      process.exit(2)
    }
  }
  if (!out.artifactDir) throw new Error('missing --artifact-dir')
  if (!out.jsonOut) throw new Error('missing --json-out')
  return out
}

function readOfficial(artifactDir) {
  const pilotSummary = path.join(artifactDir, 'official-native-path', 'reflaxe-elixir-promotion-native.summary.json')
  const resultEnv = readEnvFile(path.join(artifactDir, 'official-native-path.result.env'))
  let pilot = null
  if (fs.existsSync(pilotSummary)) {
    pilot = JSON.parse(fs.readFileSync(pilotSummary, 'utf8'))
  }
  return {
    status: resultEnv.status || (pilot && pilot.status) || 'skipped',
    marker: pilot && pilot.marker ? pilot.marker : '',
    artifactDir: fs.existsSync(path.dirname(pilotSummary)) ? path.dirname(pilotSummary) : '',
    exitCode: resultEnv.exit_code ? Number(resultEnv.exit_code) : null,
    summaryPath: fs.existsSync(pilotSummary) ? pilotSummary : '',
  }
}

function readDiagnosticLane(artifactDir, lane) {
  const safeLane = lane.replace(/[^A-Za-z0-9_.-]/g, '_')
  const laneDir = path.join(artifactDir, 'diagnostic-source-host', safeLane)
  const result = readEnvFile(path.join(laneDir, 'result.env'))
  return {
    status: result.status || 'skipped',
    exitCode: result.exit_code ? Number(result.exit_code) : null,
    failureCategory: result.failure_category || '',
    cwd: result.cwd || '',
    command: result.command || '',
    logPath: fs.existsSync(path.join(laneDir, 'native.stderr.log')) ? path.join(laneDir, 'native.stderr.log') : '',
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const lanes = args.lanes.split(',').map((s) => s.trim()).filter(Boolean)
  const diagnosticLaneNames = lanes.filter((lane) => lane !== 'official-native-path')
  const diagnostics = {}
  for (const lane of diagnosticLaneNames) diagnostics[lane] = readDiagnosticLane(args.artifactDir, lane)

  const official = readOfficial(args.artifactDir)
  const diagnosticStatuses = Object.values(diagnostics).map((lane) => lane.status)
  const diagnosticStatus = diagnosticStatuses.length === 0
    ? 'skipped'
    : (diagnosticStatuses.every((s) => s === 'pass') ? 'pass' : 'diagnostic_fail')
  const status = official.status === 'pass' ? 'pass' : official.status === 'skipped' ? diagnosticStatus : 'fail'

  const summary = {
    schema: 'reflaxe-elixir-native-verification.v1',
    status,
    marker: status === 'pass' ? 'REFLAXE_ELIXIR_NATIVE_VERIFY:PASS' : '',
    sourceRepo: args.sourceRepo,
    sourceCommit: args.sourceCommit,
    lanesRequested: lanes,
    proof: {
      officialNativePath: official,
      diagnosticSourceHostBaseline: {
        status: diagnosticStatus,
        contractRole: 'diagnostic-only',
        lanes: diagnostics,
      },
    },
  }

  fs.mkdirSync(path.dirname(args.jsonOut), { recursive: true })
  fs.writeFileSync(args.jsonOut, `${JSON.stringify(summary, null, 2)}\n`)
  console.log(`reflaxe_elixir_native_verify_summary=${args.jsonOut}`)
  if (summary.marker) console.log(summary.marker)
}

main()
