#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const repoRoot = process.cwd()
const exampleRoots = ['examples', 'packages/reflaxe.ocaml/examples']
const dedicatedExamples = {
  'examples/hxhx-embedding-subprocess': {
    command: 'npm run hxhx:example:embedding-subprocess',
    reason: 'fixture-driven embedding diagnostic example without a build.hxml entrypoint',
  },
}

function fail(message) {
  console.error(`[example-coverage-contract-check] ERROR: ${message}`)
  process.exit(1)
}

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8')
}

function exists(relativePath) {
  return fs.existsSync(path.join(repoRoot, relativePath))
}

function listDirs(relativeRoot) {
  const absoluteRoot = path.join(repoRoot, relativeRoot)
  if (!fs.existsSync(absoluteRoot)) {
    fail(`missing example root: ${relativeRoot}`)
  }
  return fs
    .readdirSync(absoluteRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(relativeRoot, entry.name).replaceAll(path.sep, '/'))
    .sort()
}

function requireIncludes(text, needle, label) {
  if (!text.includes(needle)) {
    fail(`${label} must include ${needle}`)
  }
}

function validateBuildableExample(exampleDir) {
  const readmePath = `${exampleDir}/README.md`
  if (!exists(`${exampleDir}/expected.stdout`)) {
    fail(`${exampleDir} has build.hxml but no expected.stdout runtime assertion`)
  }
  if (!exists(readmePath)) {
    fail(`${exampleDir} has build.hxml but no README.md explaining what the example proves`)
  }

  const readme = read(readmePath)
  const acceptanceOnly = exists(`${exampleDir}/ACCEPTANCE_ONLY`)
  if (acceptanceOnly) {
    requireIncludes(readme, 'test:acceptance', readmePath)
  } else {
    requireIncludes(readme, 'npm run test:examples', readmePath)
  }
  if (exists(`${exampleDir}/test.hxml`) || exists(`${exampleDir}/test.sh`)) {
    requireIncludes(readme, 'example-specific checks', readmePath)
  }

  const markers = [
    'USE_HXHX',
    'USE_HXHX_STAGE3',
    'USE_HXHX_JS',
    'ACCEPTANCE_ONLY',
  ].filter((marker) => exists(`${exampleDir}/${marker}`))

  if (markers.length === 0) {
    // Plain upstream-Haxe/reflaxe.ocaml examples are allowed, but their README must
    // make that path explicit so readers know which host compiler is being exercised.
    requireIncludes(readme, 'haxe build.hxml', readmePath)
  }

}

function validateDedicatedExample(exampleDir, spec) {
  const readmePath = `${exampleDir}/README.md`
  if (!exists(readmePath)) {
    fail(`${exampleDir} is a dedicated example but has no README.md`)
  }
  const readme = read(readmePath)
  requireIncludes(readme, spec.command, readmePath)
}

function validateExampleInventory() {
  const seen = []
  for (const root of exampleRoots) {
    for (const exampleDir of listDirs(root)) {
      seen.push(exampleDir)
      const hasBuild = exists(`${exampleDir}/build.hxml`)
      const dedicated = dedicatedExamples[exampleDir]
      if (hasBuild) {
        validateBuildableExample(exampleDir)
      } else if (dedicated) {
        validateDedicatedExample(exampleDir, dedicated)
      } else {
        fail(`${exampleDir} has no build.hxml and is not listed as a dedicated example`)
      }
    }
  }

  for (const dedicatedPath of Object.keys(dedicatedExamples)) {
    if (!seen.includes(dedicatedPath)) {
      fail(`dedicated example does not exist: ${dedicatedPath}`)
    }
  }
}

function validateWiring() {
  const packageJson = JSON.parse(read('package.json'))
  const scripts = packageJson.scripts || {}
  if (scripts['test:examples'] !== 'bash scripts/test-examples.sh') {
    fail('package.json test:examples must run scripts/test-examples.sh')
  }
  requireIncludes(scripts.test || '', 'npm run test:examples', 'package.json scripts.test')
  requireIncludes(scripts['ci:guards'] || '', 'example-coverage-contract-check.js', 'package.json scripts.ci:guards')

  const shardManifest = JSON.parse(read('scripts/ci/core-test-shards.json'))
  if (!shardManifest.assignments || !shardManifest.assignments['test:examples']) {
    fail('Core Tests shard manifest must assign test:examples to a required shard')
  }
  const ci = read('.github/workflows/ci.yml')
  requireIncludes(ci, 'npm run test:ci:shard', '.github/workflows/ci.yml')
  requireIncludes(ci, 'node scripts/ci/core-test-aggregate.js', '.github/workflows/ci.yml')

  const exampleRunner = read('scripts/test-examples.sh')
  requireIncludes(exampleRunner, 'run_example_tests', 'scripts/test-examples.sh')
  requireIncludes(exampleRunner, 'test.hxml', 'scripts/test-examples.sh')
  requireIncludes(exampleRunner, 'test.sh', 'scripts/test-examples.sh')

  const testingDoc = read('docs/01-getting-started/TESTING.md')
  requireIncludes(testingDoc, 'EXAMPLE_COVERAGE_CONTRACT:PASS', 'docs/01-getting-started/TESTING.md')
  requireIncludes(testingDoc, 'npm run guard:example-coverage', 'docs/01-getting-started/TESTING.md')

  const agents = read('AGENTS.md')
  requireIncludes(agents, 'Example Coverage Policy', 'AGENTS.md')
  requireIncludes(agents, 'EXAMPLE_COVERAGE_CONTRACT:PASS', 'AGENTS.md')
}

function main() {
  validateExampleInventory()
  validateWiring()
  console.log('[ci:guards] OK: example coverage contract is valid')
  console.log('EXAMPLE_COVERAGE_CONTRACT:PASS')
}

main()
