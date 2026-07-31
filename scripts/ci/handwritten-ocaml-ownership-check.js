#!/usr/bin/env node
/**
 * Keep handwritten OCaml at explicit target/runtime/OS/ABI boundaries.
 *
 * The compiler itself is Haxe-authored. This guard inventories every current
 * non-generated `.ml`/`.mli` file, cross-checks runtime files against the
 * hashed runtime manifest, and prevents Stage3 bootstrap shims from quietly
 * becoming supported product architecture.
 */

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const root = path.resolve(__dirname, '..', '..')
const inventoryPath = 'docs/00-project/HANDWRITTEN_OCAML_OWNERSHIP.json'
const normalized = value => value.split(path.sep).join('/')

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), 'utf8'))
}

function listRepositoryOcamlFiles() {
  const result = spawnSync(
    'git',
    ['ls-files', '--cached', '--others', '--exclude-standard', '--', '*.ml', '*.mli'],
    { cwd: root, encoding: 'utf8' }
  )
  if (result.status !== 0) {
    throw new Error(`git ls-files failed: ${(result.stderr || result.stdout).trim()}`)
  }
  return result.stdout
    .split(/\r?\n/)
    .filter(Boolean)
    .map(normalized)
    .filter(relativePath => fs.existsSync(path.join(root, relativePath)))
    .sort()
}

function readSourceMap(paths = listRepositoryOcamlFiles()) {
  return new Map(paths.map(relativePath => [
    relativePath,
    fs.readFileSync(path.join(root, relativePath), 'utf8')
  ]))
}

function stripOcamlComments(source) {
  let output = ''
  let depth = 0
  let inString = false
  let escaped = false
  for (let index = 0; index < source.length; index += 1) {
    const current = source[index]
    const next = source[index + 1]
    if (depth > 0) {
      if (current === '(' && next === '*') {
        depth += 1
        index += 1
      } else if (current === '*' && next === ')') {
        depth -= 1
        index += 1
      }
      continue
    }
    if (!inString && current === '(' && next === '*') {
      depth = 1
      index += 1
      continue
    }
    output += current
    if (inString) {
      if (escaped) escaped = false
      else if (current === '\\') escaped = true
      else if (current === '"') inString = false
    } else if (current === '"') {
      inString = true
    }
  }
  return output
}

function validateRepositoryState(sourceMap, inventory, runtimeManifest) {
  const errors = []
  const addError = message => errors.push(message)
  const requireString = (value, label) => {
    if (typeof value !== 'string' || value.trim() === '') addError(`${label} must be a non-empty string`)
  }
  const requireStringArray = (value, label) => {
    if (!Array.isArray(value) || value.length === 0 || value.some(item => typeof item !== 'string' || item.trim() === '')) {
      addError(`${label} must be a non-empty string array`)
      return false
    }
    return true
  }
  const requirePaths = (paths, label) => {
    if (!requireStringArray(paths, label)) return
    for (const relativePath of paths) {
      if (!fs.existsSync(path.join(root, relativePath))) addError(`${label} references missing path ${relativePath}`)
    }
  }

  if (inventory.schema !== 'hxhx.handwritten-ocaml-ownership.v1') addError('unsupported ownership inventory schema')
  if (inventory.marker !== 'HANDWRITTEN_OCAML_OWNERSHIP:PASS') addError('ownership inventory marker is missing')
  requireString(inventory.plainRule, 'plainRule')
  if (runtimeManifest.schemaVersion !== 1 || runtimeManifest.model !== 'reflaxe-ocaml-runtime-sources') {
    addError('unsupported runtime manifest schema/model')
  }
  if (!Array.isArray(runtimeManifest.entries) || runtimeManifest.entries.length === 0) {
    addError('runtime manifest must define entries')
    return errors
  }

  const generatedRoots = new Set()
  if (!Array.isArray(inventory.generatedArtifactRoots) || inventory.generatedArtifactRoots.length === 0) {
    addError('generatedArtifactRoots must not be empty')
  } else {
    for (const [index, entry] of inventory.generatedArtifactRoots.entries()) {
      requireString(entry.path, `generatedArtifactRoots[${index}].path`)
      requireString(entry.owner, `generatedArtifactRoots[${index}].owner`)
      requireString(entry.rule, `generatedArtifactRoots[${index}].rule`)
      if (typeof entry.path === 'string' && !entry.path.endsWith('/')) {
        addError(`generated artifact root must end with /: ${entry.path}`)
      }
      if (generatedRoots.has(entry.path)) addError(`duplicate generated artifact root ${entry.path}`)
      generatedRoots.add(entry.path)
    }
  }

  const catalog = inventory.runtimeCatalog || {}
  if (catalog.manifest !== 'packages/reflaxe.ocaml/std/runtime/runtime-manifest.json') {
    addError('runtimeCatalog.manifest must name the locked runtime manifest')
  }
  if (catalog.sourceRoot !== 'packages/reflaxe.ocaml/std/runtime/') {
    addError('runtimeCatalog.sourceRoot must name the production runtime source root')
  }

  const manifestModules = new Map()
  const runtimePaths = new Set()
  for (const entry of runtimeManifest.entries) {
    requireString(entry.module, 'runtime manifest module')
    if (manifestModules.has(entry.module)) addError(`duplicate runtime manifest module ${entry.module}`)
    if (entry.scope !== 'application' && entry.scope !== 'tooling') {
      addError(`runtime module ${entry.module} has unsupported scope ${entry.scope}`)
    }
    if (!Array.isArray(entry.files) || entry.files.length === 0) {
      addError(`runtime module ${entry.module} must list source files`)
      continue
    }
    manifestModules.set(entry.module, entry)
    for (const file of entry.files) {
      requireString(file.path, `runtime module ${entry.module} file path`)
      requireString(file.sha256, `runtime module ${entry.module} file digest`)
      const relativePath = `${catalog.sourceRoot || ''}${file.path}`
      if (runtimePaths.has(relativePath)) addError(`runtime source is owned twice: ${relativePath}`)
      runtimePaths.add(relativePath)
      if (!sourceMap.has(relativePath)) addError(`runtime manifest source is missing: ${relativePath}`)
    }
  }

  const application = catalog.applicationClassification || {}
  if (application.kind !== 'target-runtime-module') addError('application runtime modules must be classified as target-runtime-module')
  requirePaths(application.haxeDecisionOwners, 'application runtime Haxe decision owners')
  requireStringArray(application.ownerBeads, 'application runtime owner beads')
  requireString(application.whyOcaml, 'application runtime whyOcaml')
  requireString(application.readinessRule, 'application runtime readinessRule')
  requireStringArray(application.focusedEvidence, 'application runtime focusedEvidence')

  const toolingEntries = Array.isArray(catalog.toolingClassifications) ? catalog.toolingClassifications : []
  const toolingByModule = new Map()
  for (const [index, entry] of toolingEntries.entries()) {
    requireString(entry.module, `toolingClassifications[${index}].module`)
    if (toolingByModule.has(entry.module)) addError(`duplicate tooling classification ${entry.module}`)
    if (!['native-abi-adapter', 'operating-system-adapter'].includes(entry.kind)) {
      addError(`tooling module ${entry.module} has unsupported kind ${entry.kind}`)
    }
    requirePaths(entry.haxeDecisionOwners, `tooling module ${entry.module} Haxe decision owners`)
    requireStringArray(entry.ownerBeads, `tooling module ${entry.module} owner beads`)
    requireString(entry.whyOcaml, `tooling module ${entry.module} whyOcaml`)
    requireStringArray(entry.focusedEvidence, `tooling module ${entry.module} focusedEvidence`)
    toolingByModule.set(entry.module, entry)
  }
  const expectedTooling = [...manifestModules.values()].filter(entry => entry.scope === 'tooling').map(entry => entry.module).sort()
  const classifiedTooling = [...toolingByModule.keys()].sort()
  if (JSON.stringify(expectedTooling) !== JSON.stringify(classifiedTooling)) {
    addError(`tooling classifications must exactly match manifest tooling modules; expected ${expectedTooling.join(', ') || 'none'}, received ${classifiedTooling.join(', ') || 'none'}`)
  }

  const shimEntries = Array.isArray(inventory.temporarySemanticShims) ? inventory.temporarySemanticShims : []
  const shimPaths = new Set()
  for (const [index, entry] of shimEntries.entries()) {
    requireString(entry.path, `temporarySemanticShims[${index}].path`)
    if (entry.kind !== 'temporary-stage3-semantic-shim') addError(`${entry.path} has unsupported shim kind ${entry.kind}`)
    if (entry.readiness !== 'excluded') addError(`${entry.path} must remain excluded from readiness evidence`)
    if (typeof entry.knownPlaceholderSuccess !== 'boolean') addError(`${entry.path} must classify knownPlaceholderSuccess`)
    requireStringArray(entry.ownerBeads, `${entry.path} owner beads`)
    if (!entry.ownerBeads?.includes('haxe_ocaml-38gsp.1')) addError(`${entry.path} must retire through haxe_ocaml-38gsp.1`)
    requireString(entry.reason, `${entry.path} reason`)
    requireStringArray(entry.retirementEvidence, `${entry.path} retirement evidence`)
    if (shimPaths.has(entry.path)) addError(`duplicate temporary shim ${entry.path}`)
    shimPaths.add(entry.path)
    if (!sourceMap.has(entry.path)) addError(`temporary shim is missing: ${entry.path}`)
  }

  const fixtureEntries = Array.isArray(inventory.testFixtures) ? inventory.testFixtures : []
  const fixturePaths = new Set()
  for (const [index, entry] of fixtureEntries.entries()) {
    requireString(entry.path, `testFixtures[${index}].path`)
    requireString(entry.kind, `${entry.path} fixture kind`)
    requireString(entry.productionModule, `${entry.path} production module`)
    if (fixturePaths.has(entry.path)) addError(`duplicate test fixture ${entry.path}`)
    fixturePaths.add(entry.path)
    if (!sourceMap.has(entry.path)) addError(`test fixture is missing: ${entry.path}`)
  }

  const retired = new Set(Array.isArray(inventory.retiredHandwrittenModules) ? inventory.retiredHandwrittenModules : [])
  if (retired.size === 0) addError('retiredHandwrittenModules must not be empty')
  for (const relativePath of retired) {
    requireString(relativePath, 'retired handwritten module path')
    if (sourceMap.has(relativePath)) addError(`retired handwritten OCaml module returned: ${relativePath}`)
    if (runtimePaths.has(relativePath)) addError(`retired handwritten OCaml module returned to the runtime manifest: ${relativePath}`)
  }

  const classifications = new Map()
  const classify = (relativePath, kind) => {
    if (classifications.has(relativePath)) {
      addError(`${relativePath} has overlapping ownership classes ${classifications.get(relativePath)} and ${kind}`)
    } else {
      classifications.set(relativePath, kind)
    }
  }
  for (const relativePath of sourceMap.keys()) {
    const generatedRoot = [...generatedRoots].find(prefix => relativePath.startsWith(prefix))
    if (generatedRoot) classify(relativePath, 'generated-artifact')
    if (runtimePaths.has(relativePath)) classify(relativePath, 'manifest-runtime')
    if (shimPaths.has(relativePath)) classify(relativePath, 'temporary-semantic-shim')
    if (fixturePaths.has(relativePath)) classify(relativePath, 'test-fixture')
    if (!classifications.has(relativePath)) addError(`unclassified handwritten OCaml source: ${relativePath}`)
  }

  const actualRuntimeFiles = [...sourceMap.keys()].filter(relativePath => relativePath.startsWith(catalog.sourceRoot || '')).sort()
  const expectedRuntimeFiles = [...runtimePaths].sort()
  if (JSON.stringify(actualRuntimeFiles) !== JSON.stringify(expectedRuntimeFiles)) {
    addError(`runtime source files must exactly match the locked manifest; expected ${expectedRuntimeFiles.length}, observed ${actualRuntimeFiles.length}`)
  }
  const actualShimFiles = [...sourceMap.keys()].filter(relativePath => relativePath.startsWith('packages/hxhx-core/shims/')).sort()
  const expectedShimFiles = [...shimPaths].sort()
  if (JSON.stringify(actualShimFiles) !== JSON.stringify(expectedShimFiles)) {
    addError(`Stage3 shim files must exactly match the temporary-shim inventory; expected ${expectedShimFiles.length}, observed ${actualShimFiles.length}`)
  }

  const retiredSymbols = [
    ['HxHxNative', 'Lexer'].join(''),
    ['HxHxNative', 'Parser'].join(''),
    ['HxHxMacro', 'Rpc'].join(''),
  ]
  for (const relativePath of [...runtimePaths, ...shimPaths]) {
    const source = sourceMap.get(relativePath)
    if (typeof source !== 'string') continue
    const executableSource = stripOcamlComments(source)
    for (const symbol of retiredSymbols) {
      if (executableSource.includes(symbol)) addError(`${relativePath} references retired handwritten module ${symbol}`)
    }
    if (runtimePaths.has(relativePath) && /\bObj\.magic\s+0\b/.test(executableSource)) {
      addError(`${relativePath} contains placeholder Obj.magic 0 outside the explicitly excluded Stage3 shim lane`)
    }
  }

  return errors
}

function main() {
  const inventory = readJson(inventoryPath)
  const runtimeManifest = readJson(inventory.runtimeCatalog.manifest)
  const errors = validateRepositoryState(readSourceMap(), inventory, runtimeManifest)
  if (errors.length > 0) {
    console.error(`[handwritten-ocaml-ownership] ERROR:\n- ${errors.join('\n- ')}`)
    process.exit(1)
  }
  const applicationCount = runtimeManifest.entries.filter(entry => entry.scope === 'application').length
  const toolingCount = runtimeManifest.entries.filter(entry => entry.scope === 'tooling').length
  console.log(`[handwritten-ocaml-ownership] OK: ${applicationCount} application runtime modules, ${toolingCount} tooling adapters, ${inventory.temporarySemanticShims.length} excluded Stage3 shims, and ${inventory.testFixtures.length} native fixtures are classified`)
  console.log(inventory.marker)
}

if (require.main === module) main()

module.exports = {
  listRepositoryOcamlFiles,
  readSourceMap,
  stripOcamlComments,
  validateRepositoryState,
}
