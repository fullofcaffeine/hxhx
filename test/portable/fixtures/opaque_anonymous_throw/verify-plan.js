const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const fixture = __dirname
const repo = path.resolve(fixture, '../../../..')
const output = path.join(fixture, 'out')
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-anonymous-throw-proof-'))
const cases = []

/** Keeps compiler errors separate from the semantic rejection asserted by each case. */
function haxe(args) {
  const result = spawnSync(process.env.HAXE_BIN || 'haxe', args, {
    cwd: repo, encoding: 'utf8', maxBuffer: 50 * 1024 * 1024
  })
  if (result.error) throw result.error
  assert.equal(result.status, 0, result.stdout + result.stderr)
  return result.stdout
}

try {
  /** Reseals an independent report so its rejection cannot come from a stale checksum. */
  function corrupt(label, pattern, mutate) {
    const directory = path.join(temporary, label)
    fs.cpSync(output, directory, {
      recursive: true, filter: source => path.basename(source) !== '_build'
    })
    const reportPath = path.join(directory, 'ocaml_lowering_report.json')
    const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
    const control = report.controls.find(row => row.payload?.proofId === 'opaque-anonymous-container-throw-v1')
    assert(control, 'fixture must exercise the opaque anonymous exception proof')
    mutate(control)
    fs.writeFileSync(reportPath, JSON.stringify(report))
    haxe(['-cp', 'scripts/ci', '-cp', 'packages/reflaxe.ocaml/src',
      '--run', 'RecomputeLoweringControlRevision', reportPath])
    cases.push({ label, directory, pattern })
  }

  const crossing = /invalid represented Haxe exception crossing/
  corrupt('wrong-conversion', crossing, row => {
    row.payload.conversion = 'preserve-dynamic-throw-carrier'
  })
  corrupt('wrong-proof', crossing, row => {
    row.payload.proofId = 'dynamic-carrier-throw-control-v1'
  })
  corrupt('wrong-signal', crossing, row => { row.payload.signalCarrierTypeId = 'int' })
  corrupt('wrong-output-carrier', /Control decision.*(representation|carrier|crossing)/, row => {
    row.payload.outputCarrierTypeId = 'int'
  })
  corrupt('invented-layout-revision', /Control decision.*(representation|carrier|crossing)/, row => {
    row.payload.representationRevision = 'sha256:' + '0'.repeat(64)
  })

  const reports = JSON.parse(haxe(['-cp', 'packages/reflaxe.ocaml/src', '-cp', fixture,
    '--macro', 'nullSafety("reflaxe.ocaml")', '--run', 'InspectReports',
    fixture, output, ...cases.map(entry => entry.directory)]))
  assert.equal(reports.length, cases.length + 1)
  assert.equal(reports[0].summary.valid, true, JSON.stringify(reports[0]))
  for (const [index, entry] of cases.entries()) {
    const report = reports[index + 1]
    assert.equal(report.summary.valid, false, `public inspection accepted ${entry.label}`)
    assert.match(JSON.stringify(report), entry.pattern)
  }
  console.log('OPAQUE_ANONYMOUS_THROW_PLAN:PASS')
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}
