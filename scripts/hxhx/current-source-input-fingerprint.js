#!/usr/bin/env node
/**
 * Build the content fingerprint used by the developer-only current-source
 * compiler cache.
 *
 * The strict proof path remains commit-bound. This helper answers a narrower
 * local-development question: would a fresh `HXHX_FORCE_STAGE0=1` build read
 * different compiler, runtime, configuration, or toolchain inputs?
 */

'use strict'

const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')

const SCHEMA = 'hxhx.current-source-inputs.v1'
const FIXTURE_SCHEMA = 'hxhx.current-source-input-fixture.v1'

const REPO_INPUT_GROUPS = [
  {
    id: 'compiler-source',
    paths: ['packages/hxhx/src', 'packages/hxhx-core/src'],
  },
  {
    id: 'target-runtime-and-templates',
    paths: [
      'packages/hxhx-core/shims',
      'packages/hxhx-core/source-templates',
      'packages/reflaxe.ocaml/src',
      'packages/reflaxe.ocaml/std',
    ],
  },
  {
    id: 'build-configuration',
    paths: [
      '.haxerc',
      'lix_scope.json',
      'haxe_libraries',
      'packages/hxhx/build.hxml',
      'packages/reflaxe.ocaml/extraParams.hxml',
      'packages/reflaxe.ocaml/haxelib.json',
      'scripts/hxhx/build-hxhx.sh',
      'scripts/hxhx/build-current-source-hxhx.sh',
      'scripts/hxhx/current-source-input-fingerprint.js',
      'scripts/hxhx/haxe-server.sh',
      'scripts/hxhx/sanitize-stage3-emit-dir.sh',
    ],
  },
]

const BUILD_ENVIRONMENT_NAMES = [
  'HAXE_BIN',
  'HAXE_CONNECT',
  'HAXE_LIBCACHE',
  'HAXE_STD_PATH',
  'HXHX_STAGE0_USE_REPO_SERVER',
  'HXHX_STAGE0_KEEP_REPO_SERVER',
  'HXHX_ALLOW_INCOMPLETE_REFLAXE_SERVER_REUSE',
  'HXHX_STAGE0_PROGRESS',
  'HXHX_STAGE0_TELEMETRY',
  'HXHX_STAGE0_TELEMETRY_DETAIL',
  'HXHX_STAGE0_TELEMETRY_CLASS',
  'HXHX_STAGE0_TELEMETRY_FIELD',
  'HXHX_STAGE0_OCAML_BUILD',
  'HXHX_STAGE0_PREFER_NATIVE',
  'HXHX_STAGE0_DISABLE_PREPASSES',
  'HXHX_STAGE0_NO_INLINE',
  'HXHX_STAGE0_NO_OPT',
  'HXHX_STAGE0_NO_NATIVE_PARSER',
  'HXHX_STAGE0_NO_HX_PARSER',
  'HXHX_STAGE0_NO_EXPR_MACROS',
  'HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST',
  'HXHX_STAGE0_NO_INTERNAL_TOOLS',
  'HXHX_STAGE0_NO_DISPLAY',
  'HXHX_STAGE0_NO_SOURCE_NORMALIZE_EXTRACT',
  'HXHX_STAGE0_NO_NATIVE_DECODE_EXTRACT',
  'HXHX_STAGE0_NO_PARSER_SCAN_EXTRACT',
  'HXHX_STAGE0_OCAML_ONLY',
  'HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY',
  'HXHX_STAGE0_REFLAXE_SRC',
  'OCAMLPARAM',
  'OCAMLRUNPARAM',
  'OCAMLLIB',
  'OCAML_PATH',
  'OCAMLFIND_CONF',
  'OCAMLFIND_TOOLCHAIN',
  'CAML_LD_LIBRARY_PATH',
  'OPAM_SWITCH_PREFIX',
  'OPAMROOT',
  'DUNE_PROFILE',
  'PKG_CONFIG_PATH',
  'CC',
  'CXX',
  'CFLAGS',
  'CPPFLAGS',
  'LDFLAGS',
]

function fail(message) {
  throw new Error(message)
}

function usage() {
  console.log(`Usage: node scripts/hxhx/current-source-input-fingerprint.js [options]

Options:
  --root <path>            Repository root (default: current repository)
  --json-out <path>        Write the complete component report atomically
  --fixture-config <path>  Use deterministic fixture paths/tool identities
  -h, --help               Show this help

Environment:
  HXHX_CURRENT_SOURCE_FINGERPRINT_FIXTURE  Fixture equivalent of --fixture-config`)
}

function readValue(argv, index, flag) {
  if (index + 1 >= argv.length) fail(`${flag} requires a value`)
  return argv[index + 1]
}

function parseArgs(argv, env = process.env) {
  const options = {
    root: path.resolve(__dirname, '../..'),
    jsonOut: '',
    fixtureConfig: env.HXHX_CURRENT_SOURCE_FINGERPRINT_FIXTURE || '',
    help: false,
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '-h' || arg === '--help') {
      options.help = true
      continue
    }
    if (arg === '--root') {
      options.root = path.resolve(readValue(argv, i, arg))
      i += 1
      continue
    }
    if (arg === '--json-out') {
      options.jsonOut = path.resolve(readValue(argv, i, arg))
      i += 1
      continue
    }
    if (arg === '--fixture-config') {
      options.fixtureConfig = path.resolve(readValue(argv, i, arg))
      i += 1
      continue
    }
    fail(`unknown option: ${arg}`)
  }
  return options
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue)
  if (value && typeof value === 'object') {
    const result = {}
    for (const key of Object.keys(value).sort()) result[key] = stableValue(value[key])
    return result
  }
  return value
}

function canonicalJson(value) {
  return JSON.stringify(stableValue(value))
}

function sha256Text(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function collectNode(absolutePath, logicalPath, entries, directoryStack = new Set()) {
  if (!fs.existsSync(absolutePath)) {
    entries.push({ path: logicalPath, kind: 'missing' })
    return
  }

  const linkStat = fs.lstatSync(absolutePath)
  if (linkStat.isSymbolicLink()) {
    const target = fs.readlinkSync(absolutePath)
    entries.push({ path: logicalPath, kind: 'symlink', target })
    const resolved = fs.realpathSync(absolutePath)
    collectResolvedNode(resolved, logicalPath, entries, directoryStack)
    return
  }
  collectResolvedNode(absolutePath, logicalPath, entries, directoryStack)
}

function collectResolvedNode(absolutePath, logicalPath, entries, directoryStack) {
  const stat = fs.statSync(absolutePath)
  if (stat.isDirectory()) {
    const realDirectory = fs.realpathSync(absolutePath)
    if (directoryStack.has(realDirectory)) fail(`symlink cycle while fingerprinting ${logicalPath}`)
    const nextStack = new Set(directoryStack)
    nextStack.add(realDirectory)
    entries.push({ path: logicalPath, kind: 'directory', mode: stat.mode & 0o777 })
    for (const name of fs.readdirSync(absolutePath).sort()) {
      collectNode(path.join(absolutePath, name), `${logicalPath}/${name}`, entries, nextStack)
    }
    return
  }
  if (stat.isFile()) {
    entries.push({
      path: logicalPath,
      kind: 'file',
      mode: stat.mode & 0o777,
      bytes: stat.size,
      sha256: sha256File(absolutePath),
    })
    return
  }
  entries.push({ path: logicalPath, kind: 'special', mode: stat.mode & 0o777 })
}

function hashPathComponent(id, root, paths, identityRoot = root) {
  const entries = []
  for (const inputPath of paths) {
    const absolute = path.isAbsolute(inputPath) ? inputPath : path.join(root, inputPath)
    const logical = path.isAbsolute(inputPath)
      ? path.relative(identityRoot, absolute) || path.basename(absolute)
      : inputPath
    collectNode(absolute, logical.replaceAll(path.sep, '/'), entries)
  }
  entries.sort((left, right) => left.path.localeCompare(right.path) || left.kind.localeCompare(right.kind))
  return {
    id,
    sha256: sha256Text(canonicalJson(entries)),
    entryCount: entries.length,
    fileCount: entries.filter(entry => entry.kind === 'file').length,
    byteCount: entries.reduce((total, entry) => total + (entry.bytes || 0), 0),
    missing: entries.filter(entry => entry.kind === 'missing').map(entry => entry.path),
  }
}

function resolveCommand(command, env = process.env, cwd = process.cwd()) {
  if (!command) return ''
  if (command.includes(path.sep)) {
    const candidate = path.isAbsolute(command) ? command : path.resolve(cwd, command)
    return fs.existsSync(candidate) ? candidate : ''
  }
  for (const directory of String(env.PATH || '').split(path.delimiter)) {
    if (!directory) continue
    const candidate = path.join(directory, command)
    if (fs.existsSync(candidate)) return candidate
  }
  return ''
}

function commandOutput(commandPath, args, env = process.env) {
  return execFileSync(commandPath, args, {
    encoding: 'utf8',
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 15000,
  }).trim()
}

function toolIdentity(id, requested, versionArgs, root, env, required = true) {
  const resolvedPath = resolveCommand(requested, env, root)
  if (!resolvedPath) {
    if (required) fail(`cannot resolve required tool ${id}: ${requested}`)
    return { id, requested, available: false }
  }
  const realPath = fs.realpathSync(resolvedPath)
  return {
    id,
    requested,
    available: true,
    resolvedPath,
    realPath,
    sha256: sha256File(realPath),
    version: commandOutput(resolvedPath, versionArgs, env).split(/\r?\n/)[0],
  }
}

function existingDirectory(candidates) {
  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      return fs.realpathSync(candidate)
    }
  }
  return ''
}

function haxeInstallation(root, haxeTool, env) {
  const haxeVersion = haxeTool.version
  let configuredVersion = ''
  const haxerc = path.join(root, '.haxerc')
  if (fs.existsSync(haxerc)) {
    try {
      configuredVersion = String(JSON.parse(fs.readFileSync(haxerc, 'utf8')).version || '')
    } catch (error) {
      fail(`cannot parse ${haxerc}: ${error.message}`)
    }
  }
  const version = configuredVersion || haxeVersion
  const candidateRoots = [
    env.HAXE_STD_PATH ? path.dirname(path.resolve(env.HAXE_STD_PATH)) : '',
    path.dirname(haxeTool.realPath),
    path.dirname(haxeTool.resolvedPath),
    path.join(os.homedir(), 'haxe', 'versions', version),
    '/opt/homebrew/lib/haxe',
    '/usr/local/lib/haxe',
  ]
  const stdPath = existingDirectory([
    env.HAXE_STD_PATH ? path.resolve(env.HAXE_STD_PATH) : '',
    ...candidateRoots.map(candidate => (candidate ? path.join(candidate, 'std') : '')),
  ])
  if (!stdPath) fail(`cannot locate the Haxe ${version} standard library for a sound cache fingerprint`)

  const compilerName = process.platform === 'win32' ? 'haxe.exe' : 'haxe'
  const compilerPath = [path.join(path.dirname(stdPath), compilerName), ...candidateRoots.map(candidate =>
    (candidate ? path.join(candidate, compilerName) : ''))]
    .find(candidate => candidate && fs.existsSync(candidate))
  return {
    version,
    stdPath,
    compilerPath: compilerPath ? fs.realpathSync(compilerPath) : haxeTool.realPath,
  }
}

function parseLibraryPathOutput(output) {
  for (const line of String(output || '').split(/\r?\n/)) {
    const candidate = line.trim()
    if (candidate && fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      return fs.realpathSync(candidate)
    }
  }
  return ''
}

function resolveScopedReflaxePath(root, env) {
  const scopedHxml = path.join(root, 'haxe_libraries/reflaxe.hxml')
  if (!fs.existsSync(scopedHxml)) return ''
  const substitutions = {
    ...env,
    HAXE_LIBCACHE: env.HAXE_LIBCACHE || path.join(os.homedir(), 'haxe/haxe_libraries'),
    SCOPE_DIR: root,
  }
  for (const rawLine of fs.readFileSync(scopedHxml, 'utf8').split(/\r?\n/)) {
    const match = rawLine.trim().match(/^-cp\s+(.+)$/)
    if (!match) continue
    let candidate = match[1].trim().replace(/^['"]|['"]$/g, '')
    let unresolved = false
    candidate = candidate.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, name) => {
      if (!Object.prototype.hasOwnProperty.call(substitutions, name)) {
        unresolved = true
        return ''
      }
      return substitutions[name]
    })
    if (unresolved) continue
    const absolute = path.isAbsolute(candidate) ? candidate : path.resolve(root, candidate)
    if (fs.existsSync(absolute) && fs.statSync(absolute).isDirectory()) return fs.realpathSync(absolute)
  }
  return ''
}

function resolveReflaxeSource(root, env) {
  if (env.HXHX_STAGE0_REFLAXE_SRC) {
    const explicit = path.resolve(env.HXHX_STAGE0_REFLAXE_SRC)
    if (!fs.existsSync(explicit)) fail(`HXHX_STAGE0_REFLAXE_SRC does not exist: ${explicit}`)
    return fs.realpathSync(explicit)
  }

  const scoped = resolveScopedReflaxePath(root, env)
  if (scoped) return scoped

  const knownCandidates = []
  if (env.HAXE_LIBCACHE) {
    knownCandidates.push(path.join(env.HAXE_LIBCACHE, 'reflaxe/4.0.0-beta/haxelib/src'))
  }
  knownCandidates.push(path.join(os.homedir(), 'haxe/haxe_libraries/reflaxe/4.0.0-beta/haxelib/src'))
  const known = existingDirectory(knownCandidates)
  if (known) return known

  for (const request of [
    { command: env.HAXELIB_BIN || 'haxelib', args: ['path', 'reflaxe'] },
    { command: 'lix', args: ['run-haxelib', 'path', 'reflaxe'] },
  ]) {
    const commandPath = resolveCommand(request.command, env, root)
    if (!commandPath) continue
    try {
      const resolved = parseLibraryPathOutput(commandOutput(commandPath, request.args, env))
      if (resolved) return resolved
    } catch (_) {
      // Try the next supported resolver. The final failure is explicit.
    }
  }
  fail('cannot resolve the external Reflaxe source used by -lib reflaxe')
}

function buildEnvironment(env, names = BUILD_ENVIRONMENT_NAMES) {
  const result = {}
  for (const name of [...names].sort()) result[name] = Object.prototype.hasOwnProperty.call(env, name) ? env[name] : null
  return result
}

function fixturePlan(root, fixturePath, env) {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'))
  if (fixture.schema !== FIXTURE_SCHEMA) fail(`fixture schema must be ${FIXTURE_SCHEMA}`)
  const resolveFixturePath = inputPath => (path.isAbsolute(inputPath) ? inputPath : path.join(root, inputPath))
  const tools = (fixture.tools || []).map(tool => {
    const resolvedPath = resolveFixturePath(tool.path)
    if (!fs.existsSync(resolvedPath)) fail(`fixture tool does not exist: ${resolvedPath}`)
    return {
      id: tool.id,
      requested: tool.path,
      available: true,
      resolvedPath,
      realPath: fs.realpathSync(resolvedPath),
      sha256: sha256File(resolvedPath),
      version: String(tool.version),
    }
  })
  return {
    source: 'fixture',
    repoInputGroups: fixture.repoInputGroups || [],
    externalComponents: (fixture.externalComponents || []).map(component => ({
      id: component.id,
      path: resolveFixturePath(component.path),
    })),
    tools,
    environment: buildEnvironment(env, fixture.buildEnvironmentNames || []),
  }
}

function productionPlan(root, env) {
  const haxeTool = toolIdentity('haxe-launcher', env.HAXE_BIN || 'haxe', ['--version'], root, env)
  const installation = haxeInstallation(root, haxeTool, env)
  const haxeCompiler = {
    id: 'haxe-compiler',
    requested: installation.compilerPath,
    available: true,
    resolvedPath: installation.compilerPath,
    realPath: installation.compilerPath,
    sha256: sha256File(installation.compilerPath),
    version: installation.version,
  }
  const ocamlcTool = toolIdentity('ocamlc', 'ocamlc', ['-version'], root, env)
  const ocamlLibraryPath = commandOutput(ocamlcTool.resolvedPath, ['-where'], env)
  if (!fs.existsSync(ocamlLibraryPath)) fail(`ocamlc -where returned a missing path: ${ocamlLibraryPath}`)
  const ocamlfindTool = toolIdentity('ocamlfind', 'ocamlfind', ['printconf', 'conf'], root, env, false)
  const findlibConfigPath = ocamlfindTool.available ? ocamlfindTool.version : ''
  return {
    source: 'host',
    repoInputGroups: REPO_INPUT_GROUPS,
    externalComponents: [
      { id: 'haxe-stdlib', path: installation.stdPath },
      { id: 'ocaml-library', path: ocamlLibraryPath },
      ...(findlibConfigPath && fs.existsSync(findlibConfigPath)
        ? [{ id: 'ocaml-findlib-config', path: findlibConfigPath }]
        : []),
      { id: 'reflaxe-source', path: resolveReflaxeSource(root, env) },
    ],
    tools: [
      haxeTool,
      haxeCompiler,
      toolIdentity('dune', 'dune', ['--version'], root, env),
      ocamlcTool,
      toolIdentity('ocamlopt', 'ocamlopt', ['-version'], root, env, false),
      toolIdentity('ocamldep', 'ocamldep', ['-version'], root, env, false),
      ocamlfindTool,
      toolIdentity('ocamlrun', 'ocamlrun', ['-version'], root, env, false),
    ],
    environment: buildEnvironment(env),
  }
}

function buildFingerprint(options, env = process.env) {
  const root = fs.realpathSync(options.root)
  const plan = options.fixtureConfig
    ? fixturePlan(root, path.resolve(options.fixtureConfig), env)
    : productionPlan(root, env)
  const components = []
  for (const group of plan.repoInputGroups) {
    components.push(hashPathComponent(group.id, root, group.paths, root))
  }
  for (const external of plan.externalComponents) {
    const realPath = fs.realpathSync(external.path)
    const component = hashPathComponent(external.id, realPath, ['.'], realPath)
    component.sourcePath = realPath
    components.push(component)
  }
  components.sort((left, right) => left.id.localeCompare(right.id))
  const identity = {
    schema: SCHEMA,
    root,
    source: plan.source,
    components,
    tools: [...plan.tools].sort((left, right) => left.id.localeCompare(right.id)),
    buildEnvironment: plan.environment,
  }
  return {
    ...identity,
    inputSha256: sha256Text(canonicalJson(identity)),
    generatedAt: new Date().toISOString(),
  }
}

function writeJsonAtomic(outputPath, report) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true })
  const temporary = `${outputPath}.tmp-${process.pid}`
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(report, null, 2)}\n`)
    fs.renameSync(temporary, outputPath)
  } finally {
    if (fs.existsSync(temporary)) fs.rmSync(temporary, { force: true })
  }
}

function main() {
  try {
    const options = parseArgs(process.argv.slice(2))
    if (options.help) {
      usage()
      return
    }
    const report = buildFingerprint(options)
    if (options.jsonOut) writeJsonAtomic(options.jsonOut, report)
    console.log(report.inputSha256)
  } catch (error) {
    console.error(`current-source-input-fingerprint: ${error.message}`)
    process.exitCode = 2
  }
}

if (require.main === module) main()

module.exports = {
  BUILD_ENVIRONMENT_NAMES,
  FIXTURE_SCHEMA,
  REPO_INPUT_GROUPS,
  SCHEMA,
  buildFingerprint,
  canonicalJson,
  hashPathComponent,
  parseArgs,
  resolveCommand,
}
