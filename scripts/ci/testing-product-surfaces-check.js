#!/usr/bin/env node
/**
 * Validates which tests and examples are allowed to support each product claim.
 *
 * This repository contains a standalone Haxe-to-OCaml target, OCaml-native
 * APIs, a Haxe compiler written in Haxe, bootstrap stages, and maintained
 * examples. A green result in one area must not be reported as proof for a
 * different area. The checked manifest gives those areas stable identities;
 * this guard rejects missing stages, unclassified examples, and QA rules that
 * explain only file paths without naming the behavior owner they protect.
 */

const fs = require('fs')
const path = require('path')

const MANIFEST_SCHEMA = 'hxhx.testing-product-surfaces.v1'
const MANIFEST_PATH = path.join(__dirname, '../../docs/00-project/TESTING_PRODUCT_SURFACES.json')
const POLICY_PATH = path.join(__dirname, 'qa-risk-policy.json')
const SCORECARD_PATH = path.join(__dirname, '../../docs/00-project/TESTING_PRODUCT_SURFACE_SCORECARDS.md')
const TESTING_GUIDE_PATH = path.join(__dirname, '../../docs/01-getting-started/TESTING.md')
const EXAMPLE_ROOTS = ['examples', 'packages/reflaxe.ocaml/examples']
const REQUIRED_SURFACES = [
  'reflaxe-ocaml-backend',
  'ocaml-native-runtime',
  'hxhx-compiler-bootstrap',
  'bootstrap-reproducibility',
  'package-downstream-examples'
]
const REQUIRED_BOOTSTRAP_STAGES = ['stage0', 'stage1', 'stage2']
const EXAMPLE_TIERS = ['flagship-application', 'capability-showcase', 'compile-only-snippet']
const SURFACE_STATUSES = ['experimental', 'admitted-slice', 'partial', 'qualified', 'release-claiming']

function invariant(condition, message) {
  if (!condition) throw new Error(message)
}

function nonEmptyStrings(value, label) {
  invariant(Array.isArray(value) && value.length > 0, `${label} must be a non-empty array`)
  for (const item of value) invariant(typeof item === 'string' && item.trim() !== '', `${label} contains an empty value`)
}

function uniqueBy(records, key, label) {
  const seen = new Set()
  for (const record of records) {
    const value = record && record[key]
    invariant(typeof value === 'string' && value !== '', `${label} needs ${key}`)
    invariant(!seen.has(value), `duplicate ${label} ${key}: ${value}`)
    seen.add(value)
  }
  return seen
}

function listMaintainedExamples(repositoryRoot) {
  const result = []
  for (const root of EXAMPLE_ROOTS) {
    const absoluteRoot = path.join(repositoryRoot, root)
    invariant(fs.existsSync(absoluteRoot), `missing example root: ${root}`)
    for (const entry of fs.readdirSync(absoluteRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) result.push(`${root}/${entry.name}`)
    }
  }
  return result.sort()
}

function validateSurface(surface) {
  invariant(typeof surface.name === 'string' && surface.name !== '', `surface ${surface.surfaceId} needs name`)
  invariant(SURFACE_STATUSES.includes(surface.status), `surface ${surface.surfaceId} has unknown status: ${surface.status}`)
  nonEmptyStrings(surface.ownerBeads, `surface ${surface.surfaceId} ownerBeads`)
  nonEmptyStrings(surface.claims, `surface ${surface.surfaceId} claims`)
  nonEmptyStrings(surface.focusedOwners, `surface ${surface.surfaceId} focusedOwners`)
  nonEmptyStrings(surface.verticalOwners, `surface ${surface.surfaceId} verticalOwners`)
  invariant(typeof surface.fullBackstopCommand === 'string' && surface.fullBackstopCommand !== '', `surface ${surface.surfaceId} needs fullBackstopCommand`)
  invariant(typeof surface.releaseCommand === 'string' && surface.releaseCommand !== '', `surface ${surface.surfaceId} needs releaseCommand`)
  invariant(typeof surface.lastCleanProof === 'string' && surface.lastCleanProof !== '', `surface ${surface.surfaceId} needs lastCleanProof`)
  nonEmptyStrings(surface.residualRisks, `surface ${surface.surfaceId} residualRisks`)
}

function validateManifest(manifest, options = {}) {
  invariant(manifest && manifest.schema === MANIFEST_SCHEMA, `unexpected testing product surface schema: ${manifest && manifest.schema}`)
  invariant(typeof manifest.strategyVersion === 'string' && manifest.strategyVersion !== '', 'manifest needs strategyVersion')
  invariant(Array.isArray(manifest.surfaces), 'surfaces must be an array')
  const surfaceIds = uniqueBy(manifest.surfaces, 'surfaceId', 'surface')
  for (const required of REQUIRED_SURFACES) invariant(surfaceIds.has(required), `missing product surface: ${required}`)
  invariant(surfaceIds.size === REQUIRED_SURFACES.length, 'manifest contains an unreviewed extra product surface')
  for (const surface of manifest.surfaces) validateSurface(surface)
  invariant(
    manifest.officialHaxeQualificationSurface === 'reflaxe-ocaml-backend',
    'official Haxe target qualification must belong only to reflaxe-ocaml-backend'
  )

  invariant(Array.isArray(manifest.bootstrapStages), 'bootstrapStages must be an array')
  const stageIds = uniqueBy(manifest.bootstrapStages, 'stageId', 'bootstrap stage')
  for (const required of REQUIRED_BOOTSTRAP_STAGES) invariant(stageIds.has(required), `missing bootstrap stage: ${required}`)
  invariant(stageIds.size === REQUIRED_BOOTSTRAP_STAGES.length, 'manifest contains an unreviewed extra bootstrap stage')
  for (const stage of manifest.bootstrapStages) {
    invariant(SURFACE_STATUSES.includes(stage.status), `bootstrap stage ${stage.stageId} has unknown status: ${stage.status}`)
    for (const field of ['name', 'claim', 'oracle', 'command']) {
      invariant(typeof stage[field] === 'string' && stage[field] !== '', `bootstrap stage ${stage.stageId} needs ${field}`)
    }
    nonEmptyStrings(stage.allowedNondeterminism, `bootstrap stage ${stage.stageId} allowedNondeterminism`)
  }

  invariant(Array.isArray(manifest.examples), 'examples must be an array')
  const examplePaths = uniqueBy(manifest.examples, 'path', 'example')
  for (const examplePath of options.examplePaths || []) {
    invariant(examplePaths.has(examplePath), `unclassified maintained example: ${examplePath}`)
  }
  for (const examplePath of examplePaths) {
    invariant((options.examplePaths || [...examplePaths]).includes(examplePath), `manifest names missing maintained example: ${examplePath}`)
  }
  for (const example of manifest.examples) {
    invariant(EXAMPLE_TIERS.includes(example.tier), `example ${example.path} has unknown tier: ${example.tier}`)
    nonEmptyStrings(example.productSurfaces, `example ${example.path} productSurfaces`)
    for (const surfaceId of example.productSurfaces) invariant(surfaceIds.has(surfaceId), `unknown product surface: ${surfaceId}`)
    invariant(Array.isArray(example.stageIds), `example ${example.path} stageIds must be an array`)
    for (const stageId of example.stageIds) invariant(stageIds.has(stageId), `example ${example.path} has unknown stage: ${stageId}`)
    invariant(typeof example.claim === 'string' && example.claim !== '', `example ${example.path} needs claim`)
    invariant(typeof example.command === 'string' && example.command !== '', `example ${example.path} needs command`)
    invariant(typeof example.runtimeClaim === 'boolean', `example ${example.path} runtimeClaim must be boolean`)
    if (example.tier === 'compile-only-snippet') invariant(example.runtimeClaim === false, `compile-only example ${example.path} cannot claim runtime behavior`)
  }

  if (options.qaPolicy) {
    nonEmptyStrings(options.qaPolicy.defaultUnknownSemanticOwners, 'QA policy defaultUnknownSemanticOwners')
    nonEmptyStrings(options.qaPolicy.defaultUnknownProductSurfaces, 'QA policy defaultUnknownProductSurfaces')
    for (const surfaceId of options.qaPolicy.defaultUnknownProductSurfaces) {
      invariant(surfaceIds.has(surfaceId), `QA policy names unknown default product surface: ${surfaceId}`)
    }
    invariant(Array.isArray(options.qaPolicy.rules), 'QA policy rules must be an array')
    for (const rule of options.qaPolicy.rules) {
      nonEmptyStrings(rule.semanticOwners, `QA rule ${rule.id} semanticOwners`)
      invariant(Array.isArray(rule.productSurfaces), `QA rule ${rule.id} productSurfaces must be an array`)
      for (const surfaceId of rule.productSurfaces) invariant(surfaceIds.has(surfaceId), `QA rule ${rule.id} names unknown product surface: ${surfaceId}`)
    }
  }

  return manifest
}

function requireText(filePath, values) {
  const contents = fs.readFileSync(filePath, 'utf8')
  for (const value of values) invariant(contents.includes(value), `${path.basename(filePath)} must mention ${value}`)
}

function main() {
  const repositoryRoot = path.resolve(__dirname, '../..')
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'))
  const qaPolicy = JSON.parse(fs.readFileSync(POLICY_PATH, 'utf8'))
  validateManifest(manifest, {
    examplePaths: listMaintainedExamples(repositoryRoot),
    qaPolicy
  })
  requireText(SCORECARD_PATH, [...REQUIRED_SURFACES, ...REQUIRED_BOOTSTRAP_STAGES])
  requireText(TESTING_GUIDE_PATH, [
    'Behavior-first change workflow',
    'independent oracle',
    'tracer bullet',
    'lowest faithful',
    'double lock',
    'TESTING_PRODUCT_SURFACE_SCORECARDS.md'
  ])
  console.log('TESTING_PRODUCT_SURFACES:PASS')
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[testing-product-surfaces-check] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  EXAMPLE_TIERS,
  MANIFEST_SCHEMA,
  REQUIRED_BOOTSTRAP_STAGES,
  REQUIRED_SURFACES,
  listMaintainedExamples,
  validateManifest
}
