#!/usr/bin/env node
/**
 * Proves that product evidence cannot silently lose a claim surface or example.
 *
 * A scorecard is the checked map from one product claim to the tests allowed to
 * support it. These fixtures use small in-memory manifests so failures explain
 * the missing contract without starting a compiler or target toolchain.
 */

const assert = require('assert')
const {
  REQUIRED_BOOTSTRAP_STAGES,
  REQUIRED_SURFACES,
  validateManifest
} = require('./testing-product-surfaces-check')

function scorecard(surfaceId) {
  return {
    surfaceId,
    name: surfaceId,
    ownerBeads: ['test-owner'],
    status: 'partial',
    claims: ['one bounded claim'],
    focusedOwners: ['npm run test:focused'],
    verticalOwners: ['npm run test:vertical'],
    fullBackstopCommand: 'npm test',
    releaseCommand: 'npm run test:release',
    lastCleanProof: 'fixture proof',
    residualRisks: ['fixture-only risk']
  }
}

function validManifest() {
  return {
    schema: 'hxhx.testing-product-surfaces.v1',
    strategyVersion: 'fixture-v1',
    officialHaxeQualificationSurface: 'reflaxe-ocaml-backend',
    surfaces: REQUIRED_SURFACES.map(scorecard),
    bootstrapStages: REQUIRED_BOOTSTRAP_STAGES.map(stageId => ({
      stageId,
      name: stageId,
      status: 'partial',
      claim: 'one bounded stage claim',
      oracle: 'manually authored fixture expectation',
      command: 'npm run test:stage',
      allowedNondeterminism: ['fixture path']
    })),
    examples: [{
      path: 'examples/Demo',
      tier: 'capability-showcase',
      productSurfaces: ['package-downstream-examples'],
      stageIds: [],
      claim: 'the example compiles and runs',
      command: 'npm run test:examples',
      runtimeClaim: true
    }]
  }
}

validateManifest(validManifest(), {
  examplePaths: ['examples/Demo'],
  qaPolicy: {
    defaultUnknownSemanticOwners: ['unclassified-change'],
    defaultUnknownProductSurfaces: REQUIRED_SURFACES,
    rules: [{
      id: 'fixture-rule',
      semanticOwners: ['example-runner'],
      productSurfaces: ['package-downstream-examples']
    }]
  }
})

const missingStage = validManifest()
missingStage.bootstrapStages = missingStage.bootstrapStages.filter(stage => stage.stageId !== 'stage2')
assert.throws(
  () => validateManifest(missingStage, { examplePaths: ['examples/Demo'] }),
  /missing bootstrap stage: stage2/
)

const missingExample = validManifest()
missingExample.examples = []
assert.throws(
  () => validateManifest(missingExample, { examplePaths: ['examples/Demo'] }),
  /unclassified maintained example: examples\/Demo/
)

const unknownSurface = validManifest()
unknownSurface.examples[0].productSurfaces = ['not-a-product']
assert.throws(
  () => validateManifest(unknownSurface, { examplePaths: ['examples/Demo'] }),
  /unknown product surface: not-a-product/
)

const pathOnlyRule = validManifest()
assert.throws(
  () => validateManifest(pathOnlyRule, {
    examplePaths: ['examples/Demo'],
    qaPolicy: {
      defaultUnknownSemanticOwners: ['unclassified-change'],
      defaultUnknownProductSurfaces: REQUIRED_SURFACES,
      rules: [{ id: 'path-only' }]
    }
  }),
  /QA rule path-only semanticOwners must be a non-empty array/
)

console.log('TESTING_PRODUCT_SURFACES_FIXTURES:PASS')
