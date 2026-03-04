#!/usr/bin/env node
/**
 * native-plugin-happy-path-check.js
 *
 * Auditable native plugin happy-path gate:
 * - build a minimal ocaml-dynlink plugin artifact;
 * - compile via hxhx with manifest-based plugin loading;
 * - assert backend selection switches to plugin provider implementation.
 */

const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const buildBackendPluginScript = path.join(root, 'scripts', 'hxhx', 'build-backend-plugin.sh')
const buildHxhxScript = path.join(root, 'scripts', 'hxhx', 'build-hxhx.sh')
const fixtureDir = path.join(root, 'test', 'fixtures', 'native_backend_plugin')
const ocamloptWrapper = path.join(root, 'scripts', 'hxhx', 'ocamlopt-with-threads.sh')
const defaultHxhxBuildTimeoutSecs = 1800
const hxhxBinCandidates = [
  path.join(root, 'packages', 'hxhx', 'bootstrap_work', '_build', 'default', 'out.exe'),
  path.join(root, 'packages', 'hxhx', 'bootstrap_work', '_build', 'default', 'out.bc'),
  path.join(root, 'packages', 'hxhx', 'out', '_build', 'default', 'out.exe'),
  path.join(root, 'packages', 'hxhx', 'out', '_build', 'default', 'out.bc'),
]

function fail(message) {
  console.error(`[native-plugin-happy-path] ERROR: ${message}`)
  process.exit(1)
}

function run(cmd, args, options = {}) {
  const timeoutMs = options.timeoutMs || undefined
  const result = cp.spawnSync(cmd, args, {
    cwd: root,
    encoding: 'utf8',
    env: { ...process.env, ...(options.env || {}) },
    maxBuffer: 20 * 1024 * 1024,
    timeout: timeoutMs,
  })
  if (result.error) {
    if (result.error.code === 'ETIMEDOUT' && timeoutMs != null) {
      fail(`${cmd} ${args.join(' ')} timed out after ${timeoutMs}ms`)
    }
    fail(`${cmd} failed to start: ${result.error.message}`)
  }
  const stdout = result.stdout || ''
  const stderr = result.stderr || ''
  const combined = `${stdout}${stderr}`
  if (result.status !== 0 && !options.allowFailure) {
    fail(`${cmd} ${args.join(' ')} failed (exit ${result.status}).\n${combined}`)
  }
  return { status: result.status || 0, stdout, stderr, combined }
}

function requireFile(filePath, label) {
  if (!fs.existsSync(filePath)) {
    fail(`missing ${label}: ${filePath}`)
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
    return fromEnv
  }
  const fromBuildDirs = firstExistingHxhxBin()
  if (fromBuildDirs != null) {
    return fromBuildDirs
  }
  const buildTimeoutRaw = process.env.HXHX_NATIVE_PLUGIN_HXHX_BUILD_TIMEOUT_SECS || `${defaultHxhxBuildTimeoutSecs}`
  const buildTimeoutSecs = Number(buildTimeoutRaw)
  if (!Number.isInteger(buildTimeoutSecs) || buildTimeoutSecs <= 0) {
    fail(`invalid HXHX_NATIVE_PLUGIN_HXHX_BUILD_TIMEOUT_SECS='${buildTimeoutRaw}' (expected positive integer seconds)`)
  }
  const preferStage0SourceBuild = process.env.HXHX_NATIVE_PLUGIN_RUNTIME_STAGE0_BUILD === '1'
  const buildEnv = preferStage0SourceBuild ? { HXHX_FORCE_STAGE0: '1' } : {}
  const result = run('bash', [buildHxhxScript], {
    env: buildEnv,
    timeoutMs: buildTimeoutSecs * 1000,
  })
  const lines = result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
  const maybePath = lines.length > 0 ? lines[lines.length - 1] : ''
  if (!maybePath || !fs.existsSync(maybePath)) {
    fail(`failed to resolve hxhx binary from ${buildHxhxScript}`)
  }
  return maybePath
}

function assertContains(haystack, re, label) {
  if (!re.test(haystack)) {
    fail(`expected ${label} (${re}) in output.\n${haystack}`)
  }
}

function main() {
  requireFile(buildBackendPluginScript, 'backend plugin build script')
  requireFile(buildHxhxScript, 'hxhx build script')
  requireFile(fixtureDir, 'native backend plugin fixture directory')

  const hxhxBin = resolveHxhxBin()
  const pluginArtifactExt = hxhxBin.endsWith('.bc') ? 'cma' : 'cmxs'

  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'native-plugin-happy-path-'))
  const pluginOut = path.join(tmpRoot, 'plugin_out')
  const fixtureSrc = path.join(tmpRoot, 'src')
  fs.mkdirSync(pluginOut, { recursive: true })
  fs.mkdirSync(fixtureSrc, { recursive: true })

  const env = {}
  if (!process.env.OCAMLOPT && fs.existsSync(ocamloptWrapper)) {
    env.OCAMLOPT = ocamloptWrapper
  }

  const pluginArtifactRel = `plugins/hxhx_backend_plugin_fixture.${pluginArtifactExt}`
  run('bash', [
    buildBackendPluginScript,
    '--plugin-id', 'fixture.native.backend.plugin',
    '--plugin-version', '0.1.0',
    '--kind', 'ocaml-dynlink',
    '--source-dir', fixtureDir,
    '--dune-target', `hxhx_backend_plugin_fixture.${pluginArtifactExt}`,
    '--entry', pluginArtifactRel,
    '--target-id', 'js-native',
    '--out-dir', pluginOut,
  ], { env })

  const manifestRel = path.join(pluginOut, 'backend-plugin.json')
  const artifactRel = path.join(pluginOut, pluginArtifactRel)
  requireFile(manifestRel, 'generated plugin manifest')
  requireFile(artifactRel, 'generated plugin artifact')

  fs.writeFileSync(path.join(fixtureSrc, 'Main.hx'), [
    'class Main {',
    '\tstatic function main() {',
    '\t\tvar sum = 0;',
    '\t\tfor (i in 1...4)',
    '\t\t\tsum += i;',
    '\t\tSys.println("sum=" + sum);',
    '\t}',
    '}',
    '',
  ].join('\n'))

  function compileWithManifest(manifestPath, outDir) {
    fs.mkdirSync(outDir, { recursive: true })
    const runResult = run(hxhxBin, [
      '--js', path.join(outDir, 'main.js'),
      '--hxhx-no-run',
      '-cp', fixtureSrc,
      '-main', 'Main',
      '--hxhx-out', outDir,
      '-D', 'hxhx_backend_provider=backend.js.JsBackend',
      '-D', `hxhx_backend_plugin_manifest=${manifestPath}`,
    ], {
      env: {
        HXHX_FORBID_STAGE0: '1',
        HXHX_TRACE_BACKEND_SELECTION: '1',
        HXHX_TRACE_BACKEND_PROVIDERS: '1',
      },
    })
    assertContains(runResult.combined, /^backend_selected_impl=provider\/js-native-wrapper$/m, 'plugin backend selection marker')
    requireFile(path.join(outDir, 'main.js'), 'compiled JS output')
    const nodeResult = run('node', [path.join(outDir, 'main.js')])
    assertContains(nodeResult.combined, /^sum=6$/m, 'runtime output marker')
  }

  compileWithManifest(manifestRel, path.join(tmpRoot, 'out_rel'))

  const manifestAbs = path.join(pluginOut, 'backend-plugin-absolute.json')
  const manifestJson = JSON.parse(fs.readFileSync(manifestRel, 'utf8'))
  manifestJson.backend.entry = path.resolve(artifactRel)
  fs.writeFileSync(manifestAbs, `${JSON.stringify(manifestJson, null, 2)}\n`)
  compileWithManifest(manifestAbs, path.join(tmpRoot, 'out_abs'))

  console.log(`plugin_runtime_manifest_relative=${manifestRel}`)
  console.log(`plugin_runtime_manifest_absolute=${manifestAbs}`)
  console.log('NATIVE_PLUGIN_HAPPY_PATH:PASS')
}

main()
