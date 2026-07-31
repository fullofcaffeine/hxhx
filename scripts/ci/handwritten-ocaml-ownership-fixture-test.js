#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const {
  readSourceMap,
  validateRepositoryState,
} = require('./handwritten-ocaml-ownership-check.js')

const root = path.resolve(__dirname, '..', '..')
const inventory = JSON.parse(fs.readFileSync(path.join(root, 'docs/00-project/HANDWRITTEN_OCAML_OWNERSHIP.json'), 'utf8'))
const runtimeManifest = JSON.parse(fs.readFileSync(path.join(root, inventory.runtimeCatalog.manifest), 'utf8'))
const sources = readSourceMap()

function assertNoErrors(errors, label) {
  if (errors.length > 0) throw new Error(`${label}:\n- ${errors.join('\n- ')}`)
}

function assertRejected(label, mutate, expectedText) {
  const nextSources = new Map(sources)
  const nextInventory = JSON.parse(JSON.stringify(inventory))
  const nextManifest = JSON.parse(JSON.stringify(runtimeManifest))
  mutate(nextSources, nextInventory, nextManifest)
  const errors = validateRepositoryState(nextSources, nextInventory, nextManifest)
  if (!errors.some(error => error.includes(expectedText))) {
    throw new Error(`${label}: expected an error containing ${JSON.stringify(expectedText)}, got:\n- ${errors.join('\n- ')}`)
  }
}

assertNoErrors(validateRepositoryState(sources, inventory, runtimeManifest), 'repository baseline')

assertRejected(
  'unclassified production source',
  nextSources => nextSources.set('packages/hxhx-core/shims/SurpriseCompiler.ml', 'let compile source = source\n'),
  'unclassified handwritten OCaml source'
)
assertRejected(
  'runtime bypasses manifest',
  nextSources => nextSources.set('packages/reflaxe.ocaml/std/runtime/HxShadowCompiler.ml', 'let compile source = source\n'),
  'unclassified handwritten OCaml source'
)
assertRejected(
  'shim readiness inflation',
  (_nextSources, nextInventory) => {
    nextInventory.temporarySemanticShims.find(entry => entry.path.endsWith('HxBootProcess.ml')).readiness = 'supported'
  },
  'must remain excluded from readiness evidence'
)
assertRejected(
  'tooling adapter missing classification',
  (_nextSources, nextInventory) => {
    nextInventory.runtimeCatalog.toolingClassifications =
      nextInventory.runtimeCatalog.toolingClassifications.filter(entry => entry.module !== 'HxHxCompilerServer')
  },
  'tooling classifications must exactly match manifest tooling modules'
)
assertRejected(
  'placeholder admitted as runtime',
  nextSources => {
    const target = 'packages/reflaxe.ocaml/std/runtime/HxHxCompilerServer.ml'
    nextSources.set(target, `${nextSources.get(target)}\nlet fake_success () = Obj.magic 0\n`)
  },
  'placeholder Obj.magic 0'
)
assertRejected(
  'retired parser returns',
  nextSources => nextSources.set(
    `packages/reflaxe.ocaml/std/runtime/${['HxHxNative', 'Parser'].join('')}.ml`,
    'let parse source = source\n'
  ),
  'retired handwritten OCaml module returned'
)

const generatedSources = new Map(sources)
generatedSources.set('test/snapshot/ownership-fixture/intended/Main.ml', 'let main () = ()\n')
assertNoErrors(validateRepositoryState(generatedSources, inventory, runtimeManifest), 'generated artifact classification')

console.log('[ci:guards] OK: handwritten OCaml ownership negative fixtures pass')
