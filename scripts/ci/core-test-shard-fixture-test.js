#!/usr/bin/env node
/** Contract tests for complete shard coverage and fail-closed aggregation. */

const childProcess = require('child_process')
const fs = require('fs')
const path = require('path')
const {
  evaluateAggregateResults,
  jobsRequiredAtTier,
  loadPlan,
  parseAggregateCommands,
  validateManifest
} = require('./core-test-shards')
const { loadPlan: loadMacroHostPlan } = require('./macro-host-test-artifact')

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
    'test-shards',
    'hxhx-e2e'
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
  const expectedShardMinimumTiers = {
    compiler: 'Q2',
    'macro-host-integration': 'Q2',
    'target-packages': 'Q2',
    'hxhx-targets': 'Q3'
  }
  const expectedJobMinimumTiers = {
    guards: 'Q1',
    'stage0-free-smoke': 'Q2',
    'js-native-smoke': 'Q2',
    'plugin-matrix': 'Q2',
    'test-shards': 'Q2',
    'hxhx-e2e': 'Q3'
  }
  assert(
    JSON.stringify(plan.manifest.aggregateJobMinimumTiers) === JSON.stringify(expectedJobMinimumTiers),
    `aggregate job tier ownership changed: ${JSON.stringify(plan.manifest.aggregateJobMinimumTiers)}`
  )
  for (const shard of plan.shards) {
    assert(shard.commands.length === expectedCounts[shard.id], `unexpected command count for ${shard.id}`)
    assert(
      shard.minimumTier === expectedShardMinimumTiers[shard.id],
      `unexpected minimum tier for ${shard.id}: ${shard.minimumTier}`
    )
    const listed = runScript('scripts/ci/core-test-shard.js', ['--shard', shard.id, '--list'])
    assert(listed.status === 0, `${shard.id} list command failed\n${listed.stderr}`)
    assert(
      listed.stdout.trim().split(/\r?\n/).join('\n') === shard.commands.join('\n'),
      `${shard.id} list order differs from npm test order`
    )
  }
  const macroShard = plan.shards.find(shard => shard.id === 'macro-host-integration')
  const macroHostPlan = loadMacroHostPlan(repoRoot)
  assert(macroShard.preparation.kind === 'shared-macro-host', 'macro-host shard must prepare one shared host')
  assert(
    macroShard.preparation.plan === 'scripts/ci/macro-host-integration-plan.json',
    'macro-host shard must reference the reviewed entrypoint plan'
  )
  assert(
    JSON.stringify(macroShard.commands) === JSON.stringify(macroHostPlan.value.consumerIds),
    'macro-host shard commands differ from the shared-artifact consumers'
  )

  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'))
  assert(
    packageJson.scripts['test:ci:shard'].includes('scripts/hxhx/with-heavy-run-lease.js'),
    'package.json test:ci:shard must use the cooperative local lease wrapper'
  )
  requireIncludes(packageJson.scripts['ci:guards'], 'guard:core-test-shards', 'package.json scripts.ci:guards')

  const workflowSource = fs.readFileSync(path.join(repoRoot, '.github/workflows/ci.yml'), 'utf8')
  requireIncludes(workflowSource, 'Upload shared macro-host evidence', '.github/workflows/ci.yml')
  requireIncludes(workflowSource, '.artifacts/core-test/macro-host-integration', '.github/workflows/ci.yml')

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

  const missingJobTier = structuredClone(plan.manifest)
  delete missingJobTier.aggregateJobMinimumTiers['hxhx-e2e']
  expectThrow(
    () => validateManifest(missingJobTier, plan.aggregateCommands),
    'aggregate job hxhx-e2e needs a valid minimum tier',
    'missing aggregate job tier'
  )

  const invalidShardTier = structuredClone(plan.manifest)
  invalidShardTier.shards.find(shard => shard.id === 'hxhx-targets').minimumTier = 'Q1'
  expectThrow(
    () => validateManifest(invalidShardTier, plan.aggregateCommands),
    'minimumTier must be Q2 or higher',
    'invalid shard tier'
  )

  const misplacedPreparation = structuredClone(plan.manifest)
  misplacedPreparation.shards.find(shard => shard.id === 'compiler').preparation = {
    kind: 'shared-macro-host',
    plan: 'scripts/ci/macro-host-integration-plan.json'
  }
  expectThrow(
    () => validateManifest(misplacedPreparation, plan.aggregateCommands),
    'only the macro-host-integration shard',
    'misplaced shared macro-host preparation'
  )

  assert(
    JSON.stringify(jobsRequiredAtTier(plan.manifest, 'Q0')) === '[]',
    'Q0 unexpectedly requires a compiler job'
  )
  assert(
    JSON.stringify(jobsRequiredAtTier(plan.manifest, 'Q2')) ===
      JSON.stringify(['guards', 'stage0-free-smoke', 'js-native-smoke', 'plugin-matrix', 'test-shards']),
    'Q2 job boundary changed'
  )
  assert(
    JSON.stringify(jobsRequiredAtTier(plan.manifest, 'Q3')) === JSON.stringify(expectedAggregateJobs),
    'Q3 does not require the complete Core job set'
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

  const intentionalSkipNeeds = structuredClone(successNeeds)
  intentionalSkipNeeds['test-shards'].result = 'skipped'
  assert(
    evaluateAggregateResults(plan.manifest.aggregateJobs, intentionalSkipNeeds, {
      allowSkipped: ['test-shards']
    }).length === 0,
    'aggregate rejected an explicitly authorized skipped job'
  )

  const alwaysNeeds = {
    route: { result: 'success' },
    'secret-scan': { result: 'success' }
  }
  const aggregatePass = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify({ ...alwaysNeeds, ...successNeeds }),
    CORE_TEST_QA_TIER: 'Q3'
  })
  assert(aggregatePass.status === 0, `aggregate CLI failed its pass case\n${aggregatePass.stderr}`)
  assert(aggregatePass.stdout.includes('CORE_TESTS_AGGREGATE:PASS'), 'aggregate pass marker is missing')
  const aggregateFailure = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify({ ...alwaysNeeds, ...missingNeeds }),
    CORE_TEST_QA_TIER: 'Q2'
  })
  assert(aggregateFailure.status !== 0, 'aggregate CLI accepted a missing shard result')

  const q2Needs = structuredClone(successNeeds)
  q2Needs['hxhx-e2e'].result = 'skipped'
  const aggregateQ2 = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify({ ...alwaysNeeds, ...q2Needs }),
    CORE_TEST_QA_TIER: 'Q2'
  })
  assert(aggregateQ2.status === 0, `aggregate CLI rejected the policy-authorized Q2 hxhx skip\n${aggregateQ2.stderr}`)
  assert(aggregateQ2.stdout.includes('required=5 skipped=1'), 'aggregate Q2 receipt omits its required/skip counts')

  const aggregateQ3MissingHxhx = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify({ ...alwaysNeeds, ...q2Needs }),
    CORE_TEST_QA_TIER: 'Q3'
  })
  assert(aggregateQ3MissingHxhx.status !== 0, 'aggregate CLI accepted a skipped hxhx E2E at Q3')

  const q0Needs = Object.fromEntries(plan.manifest.aggregateJobs.map(job => [job, { result: 'skipped' }]))
  const aggregateQ0 = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify({ ...alwaysNeeds, ...q0Needs }),
    CORE_TEST_QA_TIER: 'Q0'
  })
  assert(aggregateQ0.status === 0, `aggregate CLI rejected policy-authorized Q0 skips\n${aggregateQ0.stderr}`)
  assert(aggregateQ0.stdout.includes('tier=Q0'), 'aggregate Q0 receipt omits the tier')

  const q1Needs = structuredClone(q0Needs)
  q1Needs.guards.result = 'success'
  const aggregateQ1 = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify({ ...alwaysNeeds, ...q1Needs }),
    CORE_TEST_QA_TIER: 'Q1'
  })
  assert(aggregateQ1.status === 0, `aggregate CLI rejected policy-authorized Q1 skips\n${aggregateQ1.stderr}`)

  const failedRouteNeeds = { ...alwaysNeeds, ...q0Needs, route: { result: 'failure' } }
  const failedRoute = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify(failedRouteNeeds),
    CORE_TEST_QA_TIER: 'Q0'
  })
  assert(failedRoute.status !== 0, 'aggregate CLI accepted a failed route job')

  const workflow = fs.readFileSync(path.join(repoRoot, '.github/workflows/ci.yml'), 'utf8')
  requireIncludes(workflow, '  route:\n    name: QA risk route', 'Core workflow')
  requireIncludes(workflow, '  test-shards:', 'Core workflow')
  requireIncludes(workflow, '    needs: [route, guards]', 'Core test shards')
  requireIncludes(workflow, '      fail-fast: false', 'Core test shard matrix')
  requireIncludes(workflow, 'npm run test:ci:shard -- --shard "${{ matrix.shard }}"', 'Core test shard runner')
  for (const shard of plan.shards.filter(shard => shard.minimumTier === 'Q2')) {
    requireIncludes(workflow, `shard: ${shard.id}`, 'Core test shard matrix')
  }
  const q2MatrixStart = workflow.indexOf('  test-shards:')
  const q3HxhxStart = workflow.indexOf('  hxhx-e2e:')
  assert(q2MatrixStart >= 0 && q3HxhxStart > q2MatrixStart, 'Core workflow does not separate Q2 and Q3 shards')
  assert(
    !workflow.slice(q2MatrixStart, q3HxhxStart).includes('shard: hxhx-targets'),
    'Q2 matrix still contains the large hxhx target shard'
  )
  requireIncludes(workflow, '  hxhx-e2e:\n    name: Tests / hxhx target end-to-end', 'Q3 hxhx E2E job')
  requireIncludes(workflow, "needs.route.outputs.run_q3 == 'true'", 'Q3 hxhx E2E condition')
  requireIncludes(workflow, 'npm run test:ci:shard -- --shard hxhx-targets', 'Q3 hxhx E2E runner')
  requireIncludes(workflow, '  test:\n    name: Tests\n    if: ${{ always() }}', 'stable Tests aggregate')
  requireIncludes(
    workflow,
    `    needs: [route, secret-scan, ${expectedAggregateJobs.join(', ')}]`,
    'Tests aggregate prerequisites'
  )
  requireIncludes(workflow, 'CORE_TEST_NEEDS_JSON: ${{ toJSON(needs) }}', 'Tests aggregate inputs')
  requireIncludes(workflow, 'CORE_TEST_QA_TIER: ${{ needs.route.outputs.tier }}', 'Tests aggregate tier input')
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
