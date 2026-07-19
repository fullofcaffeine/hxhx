#!/usr/bin/env node
/** Contract tests for complete shard coverage and fail-closed aggregation. */

const childProcess = require('child_process')
const fs = require('fs')
const path = require('path')
const {
  evaluateAggregateResults,
  loadPlan,
  parseAggregateCommands,
  validateManifest
} = require('./core-test-shards')

const repoRoot = process.cwd()

function fail(message) {
  console.error(`[core-test-shard-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function assert(condition, message) {
  if (!condition) fail(message)
}

function expectThrow(callback, snippet, label) {
  let error = null
  try {
    callback()
  } catch (caught) {
    error = caught
  }
  assert(error, `${label} unexpectedly passed`)
  assert(error.message.includes(snippet), `${label} did not report ${JSON.stringify(snippet)}: ${error.message}`)
}

function runScript(script, args, env = process.env) {
  return childProcess.spawnSync(process.execPath, [path.join(repoRoot, script), ...args], {
    cwd: repoRoot,
    encoding: 'utf8',
    env
  })
}

function requireIncludes(content, snippet, label) {
  assert(content.includes(snippet), `${label} must include ${JSON.stringify(snippet)}`)
}

function main() {
  const plan = loadPlan(repoRoot)
  assert(plan.aggregateCommands.length === 106, `expected 106 npm test commands, found ${plan.aggregateCommands.length}`)

  const expectedAggregateJobs = [
    'guards',
    'stage0-free-smoke',
    'js-native-smoke',
    'plugin-matrix',
    'test-shards'
  ]
  assert(
    JSON.stringify(plan.manifest.aggregateJobs) === JSON.stringify(expectedAggregateJobs),
    `required aggregate jobs changed: ${JSON.stringify(plan.manifest.aggregateJobs)}`
  )

  const expectedCounts = {
    compiler: 99,
    'macro-host-integration': 3,
    'target-packages': 3,
    'hxhx-targets': 1
  }
  for (const shard of plan.shards) {
    assert(shard.commands.length === expectedCounts[shard.id], `unexpected command count for ${shard.id}`)
    const listed = runScript('scripts/ci/core-test-shard.js', ['--shard', shard.id, '--list'])
    assert(listed.status === 0, `${shard.id} list command failed\n${listed.stderr}`)
    assert(
      listed.stdout.trim().split(/\r?\n/).join('\n') === shard.commands.join('\n'),
      `${shard.id} list order differs from npm test order`
    )
  }

  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'))
  assert(
    packageJson.scripts['test:ci:shard'].includes('scripts/hxhx/with-heavy-run-lease.js'),
    'package.json test:ci:shard must use the cooperative local lease wrapper'
  )
  requireIncludes(packageJson.scripts['ci:guards'], 'guard:core-test-shards', 'package.json scripts.ci:guards')

  const invalidAggregate = structuredClone(packageJson)
  invalidAggregate.scripts.test = 'npm run one && echo hidden'
  expectThrow(
    () => parseAggregateCommands(invalidAggregate, 'test'),
    'must be exactly "npm run <script>"',
    'non-inventoried aggregate command'
  )

  const missing = structuredClone(plan.manifest)
  delete missing.assignments['test:printer']
  expectThrow(
    () => validateManifest(missing, plan.aggregateCommands),
    'not assigned to a CI shard',
    'missing shard assignment'
  )

  const unknown = structuredClone(plan.manifest)
  unknown.assignments['test:printer'] = 'not-a-shard'
  expectThrow(
    () => validateManifest(unknown, plan.aggregateCommands),
    'references unknown shard',
    'unknown shard assignment'
  )

  const extra = structuredClone(plan.manifest)
  extra.assignments['test:not-in-npm-test'] = 'compiler'
  expectThrow(
    () => validateManifest(extra, plan.aggregateCommands),
    'not present in npm test',
    'extra shard assignment'
  )

  const successNeeds = Object.fromEntries(plan.manifest.aggregateJobs.map(job => [job, { result: 'success' }]))
  assert(evaluateAggregateResults(plan.manifest.aggregateJobs, successNeeds).length === 0, 'all-success aggregate failed')
  for (const badResult of ['failure', 'cancelled', 'skipped']) {
    const needs = structuredClone(successNeeds)
    needs['test-shards'].result = badResult
    const failures = evaluateAggregateResults(plan.manifest.aggregateJobs, needs)
    assert(
      failures.length === 1 && failures[0].job === 'test-shards' && failures[0].result === badResult,
      `aggregate did not reject ${badResult}`
    )
  }
  const missingNeeds = structuredClone(successNeeds)
  delete missingNeeds['test-shards']
  const missingFailures = evaluateAggregateResults(plan.manifest.aggregateJobs, missingNeeds)
  assert(
    missingFailures.length === 1 && missingFailures[0].result === 'missing',
    'aggregate did not reject a missing required job'
  )

  const aggregatePass = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify(successNeeds)
  })
  assert(aggregatePass.status === 0, `aggregate CLI failed its pass case\n${aggregatePass.stderr}`)
  assert(aggregatePass.stdout.includes('CORE_TESTS_AGGREGATE:PASS'), 'aggregate pass marker is missing')
  const aggregateFailure = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify(missingNeeds)
  })
  assert(aggregateFailure.status !== 0, 'aggregate CLI accepted a missing shard result')

  const workflow = fs.readFileSync(path.join(repoRoot, '.github/workflows/ci.yml'), 'utf8')
  requireIncludes(workflow, '  test-shards:', 'Core workflow')
  requireIncludes(workflow, '    needs: [guards]', 'Core test shards')
  requireIncludes(workflow, '      fail-fast: false', 'Core test shard matrix')
  requireIncludes(workflow, 'npm run test:ci:shard -- --shard "${{ matrix.shard }}"', 'Core test shard runner')
  for (const shard of plan.shards) {
    requireIncludes(workflow, `shard: ${shard.id}`, 'Core test shard matrix')
  }
  requireIncludes(workflow, '  test:\n    name: Tests\n    if: ${{ always() }}', 'stable Tests aggregate')
  requireIncludes(workflow, `    needs: [${expectedAggregateJobs.join(', ')}]`, 'Tests aggregate prerequisites')
  requireIncludes(workflow, 'CORE_TEST_NEEDS_JSON: ${{ toJSON(needs) }}', 'Tests aggregate inputs')
  requireIncludes(workflow, 'node scripts/ci/core-test-aggregate.js', 'Tests aggregate command')

  const ciList = childProcess.spawnSync('npm', ['run', 'test:ci:shard', '--', '--shard', 'hxhx-targets', '--list'], {
    cwd: repoRoot,
    encoding: 'utf8',
    env: { ...process.env, CI: 'true' }
  })
  assert(ciList.status === 0, `CI-bypass shard listing failed\n${ciList.stderr}`)
  assert(ciList.stdout.includes('HAXE_FAMILY_HEAVY_RUN:CI_BYPASS'), 'CI shard did not bypass the local lease')
  assert(ciList.stdout.includes('test:hxhx-targets'), 'wrapped shard did not receive its forwarded arguments')

  console.log(`[core-test-shard-fixture-test] commands=${plan.aggregateCommands.length} shards=${plan.shards.length}`)
  console.log('CORE_TEST_SHARD_CONTRACT:PASS')
}

main()
