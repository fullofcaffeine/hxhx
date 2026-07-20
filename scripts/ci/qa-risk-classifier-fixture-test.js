#!/usr/bin/env node
/**
 * Locks the fail-safe Q0-Q4 routing behavior without starting costly jobs.
 */

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const {
  RESULT_SCHEMA,
  classify,
  loadPolicy
} = require('./qa-risk-classifier')

const loaded = loadPolicy()

function expectTier(name, options, expectedTier, expectedRuns) {
  const result = classify(options, loaded)
  assert.strictEqual(result.schema, RESULT_SCHEMA, `${name}: result schema`)
  assert.strictEqual(result.tier, expectedTier, `${name}: tier`)
  for (const [run, expected] of Object.entries(expectedRuns || {})) {
    assert.strictEqual(result.runs[run], expected, `${name}: runs.${run}`)
  }
  return result
}

expectTier('docs and beads only', {
  event: 'push',
  changedPaths: ['docs/00-project/CI_GATES.md', '.beads/issues.jsonl', 'README.md']
}, 'Q0', {
  routingAggregate: true,
  focusedTarget: false,
  standalonePackage: false,
  hxhxCanary: false,
  largeHxhxConsumer: false,
  authenticCompilerPromotion: false
})

expectTier('standalone example', {
  event: 'pull_request',
  changedPaths: ['packages/reflaxe.ocaml/examples/mini-compiler/Main.hx']
}, 'Q1', {
  standalonePackage: true,
  hxhxCanary: false
})

expectTier('documentation nested under target source', {
  event: 'push',
  changedPaths: ['packages/reflaxe.ocaml/src/reflaxe/ocaml/README.md']
}, 'Q0', {
  standalonePackage: false,
  hxhxCanary: false
})

expectTier('hxhx-specific target example', {
  event: 'pull_request',
  changedPaths: ['packages/reflaxe.ocaml/examples/hxhx-target-ocaml/Main.hx']
}, 'Q2', {
  standalonePackage: true,
  hxhxCanary: true
})

expectTier('root hxhx application example', {
  event: 'push',
  changedPaths: ['examples/hxhx-js-todoapp/src/Main.hx']
}, 'Q2', {
  standalonePackage: true,
  hxhxCanary: true
})

expectTier('standalone benchmark workload', {
  event: 'push',
  changedPaths: ['workloads/regex/build.hxml']
}, 'Q1', {
  standalonePackage: true,
  hxhxCanary: false
})

expectTier('ordinary target module', {
  event: 'push',
  changedPaths: ['packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlExpr.hx']
}, 'Q2', {
  hxhxCanary: true,
  largeHxhxConsumer: false
})

expectTier('central target representation', {
  event: 'pull_request',
  changedPaths: ['packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx']
}, 'Q3', {
  hxhxCanary: true,
  largeHxhxConsumer: true,
  authenticCompilerPromotion: true,
  hxhxReleaseEvidence: false
})

expectTier('plugin ABI', {
  event: 'push',
  changedPaths: ['packages/hxhx/src/hxhx/NativeBackendPluginHostAbi.hx']
}, 'Q3', {
  largeHxhxConsumer: true,
  authenticCompilerPromotion: true
})

expectTier('CI evidence and shard enforcement', {
  event: 'push',
  changedPaths: [
    'scripts/ci/ci-evidence-ownership.js',
    'scripts/ci/core-test-shards.json'
  ]
}, 'Q3', {
  largeHxhxConsumer: true,
  authenticCompilerPromotion: true
})

const unknown = expectTier('unknown code path', {
  event: 'push',
  changedPaths: ['new-compiler-layer/Thing.hx']
}, 'Q2', {
  hxhxCanary: true
})
assert.deepStrictEqual(unknown.unknownPaths, ['new-compiler-layer/Thing.hx'])

expectTier('mixed documentation and compiler source', {
  event: 'pull_request',
  changedPaths: ['docs/design.md', 'packages/hxhx-core/src/CompilerDriver.hx']
}, 'Q2', {
  hxhxCanary: true
})

expectTier('scheduled proof', {
  event: 'schedule',
  changedPaths: []
}, 'Q3', {
  largeHxhxConsumer: true,
  authenticCompilerPromotion: true
})

expectTier('manual release proof', {
  event: 'workflow_dispatch',
  requestedTier: 'Q4',
  changedPaths: []
}, 'Q4', {
  hxhxReleaseEvidence: true
})

expectTier('missing push inventory', {
  event: 'push',
  changedPaths: []
}, 'Q3', {
  largeHxhxConsumer: true
})

assert.throws(
  () => classify({ event: 'push', requestedTier: 'Q9', changedPaths: ['README.md'] }, loaded),
  /unknown QA tier/
)

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-qa-risk-'))
try {
  const pathsFile = path.join(tempRoot, 'changed.txt')
  const outputFile = path.join(tempRoot, 'classification.json')
  const githubOutput = path.join(tempRoot, 'github-output.txt')
  fs.writeFileSync(pathsFile, 'docs/README.md\npackages/hxhx-core/src/CompilerDriver.hx\n')
  execFileSync(process.execPath, [
    path.join(__dirname, 'qa-risk-classifier.js'),
    '--event', 'pull_request',
    '--paths-file', pathsFile,
    '--requested-tier', 'auto',
    '--producer-sha', '0123456789abcdef',
    '--output', outputFile,
    '--github-output', githubOutput
  ], { stdio: ['ignore', 'pipe', 'inherit'] })

  const receipt = JSON.parse(fs.readFileSync(outputFile, 'utf8'))
  assert.strictEqual(receipt.tier, 'Q2')
  assert.strictEqual(receipt.producerSha, '0123456789abcdef')
  assert.match(fs.readFileSync(githubOutput, 'utf8'), /^run_q2=true$/m)
  assert.match(fs.readFileSync(githubOutput, 'utf8'), /^run_q3=false$/m)
  assert.match(fs.readFileSync(githubOutput, 'utf8'), /^policy_sha256=[a-f0-9]{64}$/m)
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true })
}

console.log('QA_RISK_CLASSIFIER_FIXTURES:PASS')
