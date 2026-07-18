#!/usr/bin/env node
/** Prove developer input reuse, invalidation, and strict-proof separation. */

'use strict'

const assert = require('assert')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync, spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')
const fingerprintTool = path.join(root, 'scripts/hxhx/current-source-input-fingerprint.js')
const strictValidator = path.join(root, 'scripts/hxhx/validate-current-source-hxhx-bin.sh')
const developerValidator = path.join(root, 'scripts/hxhx/validate-developer-current-source-hxhx-bin.sh')
const selector = path.join(root, 'scripts/hxhx/current-source-hxhx-bin.sh')
const currentSourceBuilder = path.join(root, 'scripts/hxhx/build-current-source-hxhx.sh')
const fastValidator = path.join(root, 'scripts/hxhx/validate-fast-current-source-hxhx-bin.sh')
const fastSelector = path.join(root, 'scripts/hxhx/fast-current-source-hxhx-bin.sh')
const fastBuilder = path.join(root, 'scripts/hxhx/build-fast-current-source-hxhx.sh')

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: options.cwd || root,
    env: options.env || process.env,
    encoding: 'utf8',
  })
}

function git(repo, args, encoding = 'utf8') {
  return execFileSync('git', ['-C', repo, ...args], { encoding })
}

function write(filePath, content, mode) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content)
  if (mode != null) fs.chmodSync(filePath, mode)
}

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-developer-cache-'))
try {
  const repo = path.join(temp, 'repo')
  const compilerSource = path.join(repo, 'compiler/Main.hx')
  const runtimeSource = path.join(repo, 'runtime/HxRuntime.ml')
  const buildConfig = path.join(repo, 'build.hxml')
  const haxeStd = path.join(repo, 'external/haxe-std')
  const reflaxeSource = path.join(repo, 'external/reflaxe')
  const haxeTool = path.join(repo, 'tools/haxe')
  const duneTool = path.join(repo, 'tools/dune')
  const ocamlcTool = path.join(repo, 'tools/ocamlc')
  const fakeBin = path.join(repo, 'out/hxhx.bc')
  const fakeBuildDriver = path.join(repo, 'build-driver.sh')
  const buildTrace = path.join(repo, 'build-driver.trace')
  const meta = path.join(repo, 'out/hxhx-current-source.env')
  const report = path.join(repo, 'out/hxhx-current-source.inputs.json')
  const fastOut = path.join(repo, 'out_tmp_current_source_fast')
  const fastMeta = path.join(fastOut, 'hxhx-current-source-fast.env')
  const fastReport = path.join(fastOut, 'hxhx-current-source-fast.inputs.json')
  const fixtureConfig = path.join(repo, 'fingerprint-fixture.json')

  write(compilerSource, 'class Main { static function main() {} }\n')
  write(runtimeSource, 'let runtime_value = 1\n')
  write(buildConfig, '-cp compiler\n-main Main\n')
  write(path.join(haxeStd, 'Std.hx'), 'class Std {}\n')
  write(path.join(reflaxeSource, 'reflaxe/ReflectCompiler.hx'), 'package reflaxe; class ReflectCompiler {}\n')
  write(haxeTool, 'fixture haxe tool\n')
  write(duneTool, 'fixture dune tool\n')
  write(ocamlcTool, 'fixture ocamlc tool\n')
  write(fakeBin, '#!/usr/bin/env bash\nexit 0\n', 0o755)
  write(
    fakeBuildDriver,
    '#!/usr/bin/env bash\nprintf \'%s|%s|%s\\n\' "${HXHX_CURRENT_SOURCE_BUILD_PROFILE:-missing}" "${HXHX_STAGE0_DISABLE_PREPASSES:-missing}" "${HXHX_STAGE0_OUTPUT_DIR:-}" >>"$HXHX_FIXTURE_BUILD_TRACE"\nprintf \'%s\\n\' "$HXHX_FIXTURE_BIN"\n',
    0o755
  )
  write(
    fixtureConfig,
    `${JSON.stringify(
      {
        schema: 'hxhx.current-source-input-fixture.v1',
        repoInputGroups: [
          { id: 'compiler-source', paths: ['compiler'] },
          { id: 'target-runtime-and-templates', paths: ['runtime'] },
          { id: 'build-configuration', paths: ['build.hxml', 'build-driver.sh'] },
        ],
        externalComponents: [
          { id: 'haxe-stdlib', path: 'external/haxe-std' },
          { id: 'reflaxe-source', path: 'external/reflaxe' },
        ],
        tools: [
          { id: 'haxe-compiler', path: 'tools/haxe', version: '4.3.7' },
          { id: 'dune', path: 'tools/dune', version: '3.21.0' },
          { id: 'ocamlc', path: 'tools/ocamlc', version: '5.4.0' },
        ],
        buildEnvironmentNames: ['HXHX_STAGE0_DISABLE_PREPASSES', 'HXHX_STAGE0_NO_OPT'],
      },
      null,
      2
    )}\n`
  )

  git(repo, ['init', '-q'])
  git(repo, ['config', 'user.email', 'developer-cache@example.invalid'])
  git(repo, ['config', 'user.name', 'Developer Cache Fixture'])
  write(path.join(repo, 'docs/guide.md'), 'initial docs\n')
  git(repo, ['add', 'compiler', 'runtime', 'build.hxml', 'build-driver.sh', 'external', 'tools', 'fingerprint-fixture.json', 'docs'])
  git(repo, ['commit', '-q', '-m', 'initial'])

  const fixtureEnv = { ...process.env }
  delete fixtureEnv.HXHX_BIN
  delete fixtureEnv.HXHX_STAGE0_NO_OPT
  fixtureEnv.HXHX_CURRENT_SOURCE_ROOT = repo
  fixtureEnv.HXHX_CURRENT_SOURCE_META = meta
  fixtureEnv.HXHX_CURRENT_SOURCE_INPUT_REPORT = report
  fixtureEnv.HXHX_CURRENT_SOURCE_FINGERPRINT_FIXTURE = fixtureConfig
  fixtureEnv.HXHX_CURRENT_SOURCE_BUILD_DRIVER = fakeBuildDriver
  fixtureEnv.HXHX_FIXTURE_BIN = fakeBin
  fixtureEnv.HXHX_FIXTURE_BUILD_TRACE = buildTrace

  const fastEnv = {
    ...fixtureEnv,
    HXHX_FAST_CURRENT_SOURCE_OUT_DIR: fastOut,
    HXHX_FAST_CURRENT_SOURCE_META: fastMeta,
    HXHX_FAST_CURRENT_SOURCE_INPUT_REPORT: fastReport,
  }

  function fingerprint(env = fixtureEnv, outputReport = report) {
    const result = run(process.execPath, [fingerprintTool, '--root', repo, '--json-out', outputReport], {
      env,
    })
    assert.strictEqual(result.status, 0, result.stderr)
    return result.stdout.trim()
  }

  function validate(script, env = fixtureEnv) {
    return run('bash', [script, fakeBin], { cwd: repo, env })
  }

  const originalCompiler = fs.readFileSync(compilerSource, 'utf8')
  const originalRuntime = fs.readFileSync(runtimeSource, 'utf8')
  const originalTool = fs.readFileSync(haxeTool, 'utf8')
  const originalArtifact = fs.readFileSync(fakeBin)
  const built = run('bash', [currentSourceBuilder], { cwd: repo, env: fixtureEnv })
  assert.strictEqual(built.status, 0, built.stderr)
  assert.strictEqual(built.stdout.trim(), fakeBin)
  assert.match(built.stderr, /hxhx_current_source_input_sha256=/)
  const initialFingerprint = fingerprint()
  const builtMeta = fs.readFileSync(meta, 'utf8')
  assert.ok(builtMeta.includes('HXHX_BIN_BUILD_PROFILE=full'))
  assert.ok(builtMeta.includes(`HXHX_BIN_INPUT_SHA256=${initialFingerprint}`))
  assert.ok(builtMeta.includes(`HXHX_BIN_ARTIFACT_SHA256=${sha256(originalArtifact)}`))
  assert.strictEqual(fs.readFileSync(buildTrace, 'utf8'), 'full|missing|\n')

  const strictInitial = validate(strictValidator)
  assert.strictEqual(strictInitial.status, 0, strictInitial.stderr)
  const developerInitial = validate(developerValidator)
  assert.strictEqual(developerInitial.status, 0, developerInitial.stderr)
  assert.match(developerInitial.stderr, /HXHX_DEVELOPER_CURRENT_SOURCE_CACHE:REUSE/)

  const fullMetaBeforeFastBuild = fs.readFileSync(meta, 'utf8')
  const fastBuilt = run('bash', [fastBuilder], { cwd: repo, env: fastEnv })
  assert.strictEqual(fastBuilt.status, 0, fastBuilt.stderr)
  assert.strictEqual(fastBuilt.stdout.trim(), fakeBin)
  assert.strictEqual(fs.readFileSync(meta, 'utf8'), fullMetaBeforeFastBuild)
  const fastMetaText = fs.readFileSync(fastMeta, 'utf8')
  assert.ok(fastMetaText.includes('HXHX_BIN_BUILD_PROFILE=no-prepass-dev'))
  const fastFingerprint = fingerprint(
    { ...fastEnv, HXHX_STAGE0_DISABLE_PREPASSES: '1' },
    fastReport
  )
  assert.notStrictEqual(fastFingerprint, initialFingerprint)
  assert.ok(fastMetaText.includes(`HXHX_BIN_INPUT_SHA256=${fastFingerprint}`))
  assert.strictEqual(
    fs.readFileSync(buildTrace, 'utf8'),
    `full|missing|\nno-prepass-dev|1|${fastOut}\n`
  )

  const fastInitial = validate(fastValidator, fastEnv)
  assert.strictEqual(fastInitial.status, 0, fastInitial.stderr)
  assert.match(fastInitial.stderr, /profile=no-prepass-dev/)
  const strictFast = validate(strictValidator, {
    ...fastEnv,
    HXHX_CURRENT_SOURCE_META: fastMeta,
  })
  assert.notStrictEqual(strictFast.status, 0)
  assert.match(strictFast.stderr, /strict current-source proof requires HXHX_BIN_BUILD_PROFILE=full/)
  const fullDeveloperAgainstFast = validate(developerValidator, {
    ...fastEnv,
    HXHX_CURRENT_SOURCE_META: fastMeta,
  })
  assert.notStrictEqual(fullDeveloperAgainstFast.status, 0)
  assert.match(fullDeveloperAgainstFast.stderr, /expected HXHX_BIN_BUILD_PROFILE=full/)
  const fastAgainstFull = validate(fastValidator, {
    ...fastEnv,
    HXHX_FAST_CURRENT_SOURCE_META: meta,
  })
  assert.notStrictEqual(fastAgainstFull.status, 0)
  assert.match(fastAgainstFull.stderr, /expected HXHX_BIN_BUILD_PROFILE=no-prepass-dev/)

  const fastSelected = run('bash', [fastSelector], { cwd: repo, env: fastEnv })
  assert.strictEqual(fastSelected.status, 0, fastSelected.stderr)
  assert.strictEqual(fastSelected.stdout.trim(), fakeBin)
  assert.match(fastSelected.stderr, /profile=no-prepass-dev/)

  write(path.join(repo, 'docs/guide.md'), 'docs-only change\n')
  git(repo, ['add', 'docs/guide.md'])
  git(repo, ['commit', '-q', '-m', 'docs only'])

  const strictAfterDocs = validate(strictValidator)
  assert.notStrictEqual(strictAfterDocs.status, 0)
  assert.match(strictAfterDocs.stderr, /git head changed/)
  const developerAfterDocs = validate(developerValidator)
  assert.strictEqual(developerAfterDocs.status, 0, developerAfterDocs.stderr)
  assert.strictEqual(fingerprint(), initialFingerprint)

  const selected = run('bash', [selector], { cwd: repo, env: fixtureEnv })
  assert.strictEqual(selected.status, 0, selected.stderr)
  assert.strictEqual(selected.stdout.trim(), fakeBin)
  assert.match(selected.stderr, /HXHX_DEVELOPER_CURRENT_SOURCE_CACHE:REUSE/)

  write(compilerSource, `${originalCompiler}// semantic compiler edit\n`)
  const compilerChanged = validate(developerValidator)
  assert.notStrictEqual(compilerChanged.status, 0)
  assert.match(compilerChanged.stderr, /compiler input fingerprint changed/)
  assert.match(validate(fastValidator, fastEnv).stderr, /compiler input fingerprint changed/)
  const staleDiagnostic = run('bash', [selector], {
    cwd: repo,
    env: { ...fixtureEnv, HXHX_CURRENT_SOURCE_ALLOW_STALE: '1' },
  })
  assert.strictEqual(staleDiagnostic.status, 0, staleDiagnostic.stderr)
  assert.match(staleDiagnostic.stderr, /validate-current-source-hxhx-bin: warning:/)
  write(compilerSource, originalCompiler)
  assert.strictEqual(validate(developerValidator).status, 0)
  assert.strictEqual(validate(fastValidator, fastEnv).status, 0)

  write(runtimeSource, `${originalRuntime}let changed = 2\n`)
  assert.match(validate(developerValidator).stderr, /compiler input fingerprint changed/)
  write(runtimeSource, originalRuntime)

  write(haxeTool, `${originalTool}changed tool\n`)
  assert.match(validate(developerValidator).stderr, /compiler input fingerprint changed/)
  write(haxeTool, originalTool)

  const changedEnvironment = { ...fixtureEnv, HXHX_STAGE0_NO_OPT: '1' }
  assert.match(validate(developerValidator, changedEnvironment).stderr, /compiler input fingerprint changed/)

  write(fakeBin, Buffer.concat([originalArtifact, Buffer.from('changed artifact\n')]), 0o755)
  assert.match(validate(developerValidator).stderr, /compiler artifact changed/)
  assert.match(validate(fastValidator, fastEnv).stderr, /compiler artifact changed/)
  write(fakeBin, originalArtifact, 0o755)
  assert.strictEqual(validate(developerValidator).status, 0)
  assert.strictEqual(validate(fastValidator, fastEnv).status, 0)

  const storedReport = JSON.parse(fs.readFileSync(report, 'utf8'))
  assert.strictEqual(storedReport.schema, 'hxhx.current-source-inputs.v1')
  assert.strictEqual(storedReport.inputSha256, initialFingerprint)
  assert.deepStrictEqual(
    storedReport.components.map(component => component.id).sort(),
    ['build-configuration', 'compiler-source', 'haxe-stdlib', 'reflaxe-source', 'target-runtime-and-templates']
  )

  const strictSource = fs.readFileSync(strictValidator, 'utf8')
  assert.ok(!strictSource.includes('HXHX_DEVELOPER_CURRENT_SOURCE_CACHE'))
  assert.ok(!strictSource.includes('validate-developer-current-source-hxhx-bin'))
  assert.ok(strictSource.includes('HXHX_BIN_BUILD_PROFILE=full'))
  assert.ok(!strictSource.includes('no-prepass-dev'))

  console.log('DEVELOPER_CURRENT_SOURCE_CACHE_FIXTURE:PASS')
} finally {
  fs.rmSync(temp, { recursive: true, force: true })
}
