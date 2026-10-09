const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const fixture = __dirname
const repo = path.resolve(fixture, '../../../..')
const lowering = JSON.parse(fs.readFileSync(path.join(fixture, 'out/ocaml_lowering_report.json'), 'utf8'))
const conversions = lowering.containerElementConversions.filter(row => row.conversion === 'box-exact-bool-to-dynamic')
assert.equal(conversions.length, 2, 'the literal and call result each need a Boolean box')

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-bool-array-proof-'))
try {
  /** Restores the generated evidence before changing one independently checked owner. */
  function corrupt(label, mutate) {
    const output = path.join(temporary, label)
    fs.rmSync(output, { recursive: true, force: true })
    fs.cpSync(path.join(fixture, 'out'), output, {
      recursive: true, filter: source => path.basename(source) !== '_build'
    })
    const report = JSON.parse(JSON.stringify(lowering))
    mutate(report)
    fs.writeFileSync(path.join(output, 'ocaml_lowering_report.json'), JSON.stringify(report))
    return output
  }
  const wrongCarrier = corrupt('wrong-carrier', report => {
    report.unsafeOperations.find(row => row.conversionId === conversions[0].id).inputCarrierTypeId = 'int'
  })
  const missingRuntime = corrupt('missing-runtime', report => {
    report.runtimeRequirements = report.runtimeRequirements.filter(row => row.decisionId !== conversions[0].id)
    report.runtimeRequirementCount = report.runtimeRequirements.length
  })
  // Compile the public inspector once, then exercise all three evidence cases.
  const result = spawnSync(process.env.HAXE_BIN || 'haxe', [
    '-cp', 'packages/reflaxe.ocaml/src', '-cp', fixture,
    '--macro', 'nullSafety("reflaxe.ocaml")', '--run', 'VerifyInspection',
    fixture, path.join(fixture, 'out'), wrongCarrier, missingRuntime
  ], { cwd: repo, encoding: 'utf8' })
  if (result.error) throw result.error
  assert.equal(result.status, 0, result.stdout + result.stderr)
  process.stdout.write(result.stdout)
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}
