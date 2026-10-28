#!/usr/bin/env node
/** Contract tests for complete shard coverage and fail-closed aggregation. */

const childProcess = require('child_process')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
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

/** Exercise the real runner without compiling products or starting external commands. */
function checkCommandFailureReporting() {
  const source = fs.readFileSync(path.join(__dirname, 'core-test-shard.js'), 'utf8')
  const commands = ['test:first', 'test:middle', 'test:last']
  function observe(outcomes, shared = false, corrupt = false) {
    const invoked = []
    const lines = []
    const artifactResults = []
    const runtime = { argv: ['node', 'core-test-shard.js', '--shard', 'fixture'], platform: 'linux', env: {}, cwd: () => repoRoot }
    const artifact = {
      environment: {},
      verify: () => { if (corrupt) throw new Error('artifact changed') },
      failConsumer: command => artifactResults.push(`fail:${command}`),
      passConsumer: command => artifactResults.push(`pass:${command}`),
      finish: status => artifactResults.push(`finish:${status}`)
    }
    vm.runInNewContext(source, {
      process: runtime,
      console: { log: line => lines.push(line), error: line => lines.push(line) },
      require: name => {
        if (name === 'child_process') return {
          spawnSync: (executable, args) => {
            assert(executable === 'npm' && args[0] === 'run', 'runner changed npm invocation')
            invoked.push(args[1])
            return outcomes[invoked.length - 1] || { status: 0 }
          }
        }
        if (name === './core-test-shards') return { loadPlan: () => ({ shards: [{ id: 'fixture', commands }] }) }
        if (name === './macro-host-test-artifact') return { maybePrepareSharedArtifact: () => shared ? artifact : null }
        throw new Error(`unexpected runner dependency: ${name}`)
      }
    }, { filename: 'core-test-shard.js' })
    return { invoked, lines: lines.join('\n'), status: runtime.exitCode || 0, artifactResults }
  }
  const success = observe([])
  assert(success.status === 0 && success.invoked.join() === commands.join(), 'successful commands must run once in order')
  requireIncludes(success.lines, 'PASS shard=fixture', 'successful shard')
  for (const outcomes of [[{ status: 0 }, { status: 7 }], [{ status: 3 }, { status: 0 }, { status: 9 }]]) {
    const failed = observe(outcomes)
    assert(failed.invoked.join() === commands.join(), 'ordinary failure must not hide later independent commands')
    assert(failed.status === 1 && !failed.lines.includes('PASS shard=fixture'), 'a failed shard must not report success')
    outcomes.forEach((outcome, index) => {
      if (outcome.status !== 0) requireIncludes(failed.lines, `${commands[index]} failed with exit ${outcome.status}`, 'failure summary')
    })
  }
  for (const outcome of [{ error: new Error('cannot launch') }, { status: null, signal: 'SIGTERM' }, { status: null }]) {
    const aborted = observe([{ status: 0 }, outcome])
    assert(aborted.status === 1 && aborted.invoked.join() === commands.slice(0, 2).join(), 'execution failure must abort immediately')
    assert(!aborted.lines.includes('PASS shard=fixture'), 'aborted shard must not report success')
  }
  const sharedFailure = observe([{ status: 4 }], true)
  assert(sharedFailure.status === 1 && sharedFailure.invoked.length === 1, 'shared-artifact failure must stop dependent commands')
  assert(sharedFailure.artifactResults.join() === 'fail:test:first,finish:failed', 'shared artifact must record failure')
  const corrupt = observe([], true, true)
  assert(corrupt.status === 1 && corrupt.invoked.length === 0, 'invalid shared artifact must not start a consumer')
  assert(corrupt.artifactResults.join() === 'fail:test:first,finish:failed', 'invalid artifact must finish as failed')
}

/** Independent runners consume routing outputs; final aggregation still owns guard enforcement. */
function checkIndependentJobStarts(workflow) {
  const lines = workflow.split('\n')
  for (const job of ['standalone-guards', 'stage0-free-smoke', 'js-native-smoke', 'plugin-matrix', 'native-plugin-happy-path', 'test-shards', 'hxhx-e2e']) {
    const start = lines.indexOf(`  ${job}:`)
    if (start < 0) throw new Error(`missing independent job ${job}`)
    let end = start + 1
    while (end < lines.length && !/^  [a-z][a-z0-9-]*:$/.test(lines[end])) end++
    const block = lines.slice(start, end).join('\n')
    const tier = job === 'standalone-guards' ? 'q1' : job === 'hxhx-e2e' ? 'q3' : 'q2'
    if (!block.includes('    needs: [route]\n') || block.includes('needs.guards')) {
      throw new Error(`${job} must start after routing without waiting for guards`)
    }
    if (!block.includes("    if: ${{ needs.route.outputs.run_" + tier + " == 'true' }}\n")) {
      throw new Error(`${job} lost its exact routing condition`)
    }
  }
}

/** Keep the original serial command available while CI observes each C++ failure independently. */
function checkRuntimeTypeCoverage(packageJson, plan, expected) {
  const parent = 'test:m14:runtime-type-operands'
  const groups = parseAggregateCommands(packageJson, parent)
  if (plan.aggregateCommands.includes(parent)) throw new Error('serial runtime-type parent must not own a CI slot')
  const scheduled = plan.aggregateCommands.filter(command => groups.includes(command))
  if (groups.length !== 19 || JSON.stringify(scheduled) !== JSON.stringify(groups)) {
    throw new Error('runtime-type groups must run exactly once in their original order')
  }
  const expanded = groups.flatMap(group => expected.includes(`npm run ${group}`)
    ? [`npm run ${group}`]
    : packageJson.scripts[group].split(/\s*&&\s*/))
  if (JSON.stringify(expanded) !== JSON.stringify(expected)) {
    throw new Error('runtime-type split changed original commands or order')
  }
  for (const command of expected.slice(34, 50)) {
    if (!groups.some(group => command === `npm run ${group}` || packageJson.scripts[group] === command)) {
      throw new Error('each C++ runtime-type check must own an independent CI command')
    }
  }
}

function main() {
  checkCommandFailureReporting()
  const plan = loadPlan(repoRoot)
  assert(plan.aggregateCommands.length === 181, `expected 181 npm test commands, found ${plan.aggregateCommands.length}`)

  const expectedAggregateJobs = [
    'guards',
    'standalone-guards',
    'stage0-free-smoke',
    'js-native-smoke',
    'plugin-matrix',
    'native-plugin-happy-path',
    'test-shards',
    'hxhx-e2e'
  ]
  assert(
    JSON.stringify(plan.manifest.aggregateJobs) === JSON.stringify(expectedAggregateJobs),
    `required aggregate jobs changed: ${JSON.stringify(plan.manifest.aggregateJobs)}`
  )

  const expectedCounts = {
    'compiler-foundation': 18,
    'compiler-packaging': 14,
    'compiler-focused-1': 45,
    'compiler-focused-call-arguments': 1,
    'compiler-focused-2': 55,
    'compiler-focused-neko-runtime': 1,
    'compiler-focused-neko-locals': 1,
    'compiler-focused-3': 12,
    'compiler-focused-4': 7,
    'compiler-focused-cpp-closure-storage': 2,
    'compiler-focused-5': 18,
    'macro-host-integration': 3,
    portable: 1,
    'target-packages': 2,
    'hxhx-targets': 1
  }
  const expectedShardMinimumTiers = {
    'compiler-foundation': 'Q2',
    'compiler-packaging': 'Q2',
    'compiler-focused-1': 'Q2',
    'compiler-focused-call-arguments': 'Q2',
    'compiler-focused-2': 'Q2',
    'compiler-focused-neko-runtime': 'Q2',
    'compiler-focused-neko-locals': 'Q2',
    'compiler-focused-3': 'Q2',
    'compiler-focused-4': 'Q2',
    'compiler-focused-cpp-closure-storage': 'Q2',
    'compiler-focused-5': 'Q2',
    'macro-host-integration': 'Q2',
    portable: 'Q2',
    'target-packages': 'Q2',
    'hxhx-targets': 'Q3'
  }
  const expectedJobMinimumTiers = {
    guards: 'Q1',
    'standalone-guards': 'Q1',
    'stage0-free-smoke': 'Q2',
    'js-native-smoke': 'Q2',
    'plugin-matrix': 'Q2',
    'native-plugin-happy-path': 'Q2',
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
  assert(!plan.shards.some(shard => shard.id === 'compiler'), 'the timed-out broad compiler shard still exists')
  assert(
    JSON.stringify(plan.shards.find(shard => shard.id === 'compiler-focused-4').commands) === JSON.stringify([
      'test:m14:cpp-int-sub-int64',
      'test:m14:cpp-int64-mul-int',
      'test:m14:cpp-int64-mod-int',
      'test:m14:cpp-int-div-int64',
      'test:m14:cpp-guarded-control',
      'test:m14:cpp-array-push-value',
      'test:m14:cpp-string-length'
    ]),
    'C++ arithmetic setup selection must preserve all seven commands and their order'
  )
  assert(
    JSON.stringify(plan.shards.find(shard => shard.id === 'portable').commands) === JSON.stringify(['test:portable']),
    'portable fixture ownership must remain isolated from snapshots and examples'
  )
  assert(
    JSON.stringify(plan.shards.find(shard => shard.id === 'target-packages').commands) ===
      JSON.stringify(['test:snapshot', 'test:examples']),
    'target-packages must retain snapshots and examples without rerunning portable fixtures'
  )
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
  const runtimeCommands = JSON.parse(fs.readFileSync(path.join(repoRoot, 'test/fixtures/core_test_shards/runtime_type_commands.json'), 'utf8'))
  assert(runtimeCommands.length === 54, 'the runtime-type inventory must retain the original 53 commands and the Array boundary group')
  checkRuntimeTypeCoverage(packageJson, plan, runtimeCommands)
  for (const change of ['missing', 'duplicated']) {
    const invalid = structuredClone(packageJson)
    const group = 'test:m14:cpp-managed-map-type'
    invalid.scripts[group] = change === 'missing' ? '' : `${invalid.scripts[group]} && ${invalid.scripts[group]}`
    expectThrow(() => checkRuntimeTypeCoverage(invalid, plan, runtimeCommands),
      'changed original commands or order', `${change} runtime-type check`)
  }
  const missingRuntimeGroup = { ...plan, aggregateCommands: plan.aggregateCommands.filter(command => command !== 'test:m14:cpp-managed-object-map') }
  expectThrow(() => checkRuntimeTypeCoverage(packageJson, missingRuntimeGroup, runtimeCommands),
    'must run exactly once', 'runtime-type group omitted from CI')
  const repeatedRuntimeParent = { ...plan, aggregateCommands: [...plan.aggregateCommands, 'test:m14:runtime-type-operands'] }
  expectThrow(() => checkRuntimeTypeCoverage(packageJson, repeatedRuntimeParent, runtimeCommands),
    'parent must not own a CI slot', 'runtime-type parent repeated beside its children')
  assert(
    packageJson.scripts['test:ci:shard'].includes('scripts/hxhx/with-heavy-run-lease.js'),
    'package.json test:ci:shard must use the cooperative local lease wrapper'
  )
  requireIncludes(packageJson.scripts['ci:guards:core'], 'guard:core-test-shards', 'package.json scripts.ci:guards:core')
  assert(
    packageJson.scripts['ci:guards'] === 'npm run ci:guards:core && npm run ci:guards:standalone',
    'local guard aggregate must retain both required CI groups exactly once'
  )
  const standaloneCommands = [
    'test:reflaxe-ocaml:doctor',
    'test:reflaxe-ocaml:target-reuse-contract',
    'test:reflaxe-ocaml:complete-program-server'
  ]
  assert(JSON.stringify(parseAggregateCommands(packageJson, 'ci:guards:standalone')) === JSON.stringify(standaloneCommands),
    'local standalone aggregate must retain all three independent commands exactly once')
  for (const command of standaloneCommands) {
    assert(!packageJson.scripts['ci:guards:core'].split(/\s*&&\s*/).includes(`npm run ${command}`),
      `core guards must not repeat ${command}`)
  }

  const workflowSource = fs.readFileSync(path.join(repoRoot, '.github/workflows/ci.yml'), 'utf8')
  requireIncludes(workflowSource, 'Upload shared macro-host evidence', '.github/workflows/ci.yml')
  requireIncludes(workflowSource, '.artifacts/core-test/macro-host-integration', '.github/workflows/ci.yml')

  // Unmeasured partitions are explicit; malformed or invented zero timings remain invalid.
  const unmeasured = structuredClone(plan.manifest)
  unmeasured.shards[0].baselineSeconds = null
  validateManifest(unmeasured, plan.aggregateCommands)
  for (const invalidBaseline of [undefined, 0, -1, 'unmeasured']) {
    const invalidTiming = structuredClone(plan.manifest)
    invalidTiming.shards[0].baselineSeconds = invalidBaseline
    expectThrow(
      () => validateManifest(invalidTiming, plan.aggregateCommands),
      'needs a positive baselineSeconds value or explicit null until measured',
      'invalid shard timing baseline'
    )
  }

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
  misplacedPreparation.shards.find(shard => shard.id === 'compiler-foundation').preparation = {
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
      JSON.stringify(['guards', 'standalone-guards', 'stage0-free-smoke', 'js-native-smoke', 'plugin-matrix', 'native-plugin-happy-path', 'test-shards']),
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
  assert(aggregateQ2.stdout.includes('required=7 skipped=1'), 'aggregate Q2 receipt omits its required/skip counts')

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
  q1Needs['standalone-guards'].result = 'success'
  const aggregateQ1 = runScript('scripts/ci/core-test-aggregate.js', [], {
    ...process.env,
    CORE_TEST_NEEDS_JSON: JSON.stringify({ ...alwaysNeeds, ...q1Needs }),
    CORE_TEST_QA_TIER: 'Q1'
  })
  assert(aggregateQ1.status === 0, `aggregate CLI rejected policy-authorized Q1 skips\n${aggregateQ1.stderr}`)

  // Both independent plugin workloads remain mandatory after they stop sharing a job budget.
  for (const job of ['plugin-matrix', 'native-plugin-happy-path']) {
    for (const tier of ['Q2', 'Q3']) {
      for (const result of ['failure', 'cancelled', 'skipped', 'missing']) {
        const needs = structuredClone({ ...alwaysNeeds, ...successNeeds })
        if (result === 'missing') delete needs[job]
        else needs[job].result = result
        const rejected = runScript('scripts/ci/core-test-aggregate.js', [], {
          ...process.env,
          CORE_TEST_NEEDS_JSON: JSON.stringify(needs),
          CORE_TEST_QA_TIER: tier
        })
        assert(rejected.status !== 0, `${tier} aggregate accepted ${job}=${result}`)
        assert(rejected.stderr.includes(`required job ${job} result=${result}`), `${tier} lost the plugin failure reason`)
      }
    }
  }

  // Every Q1 guard owner must succeed, even when all other independent jobs pass.
  for (const job of ['guards', 'standalone-guards']) {
    for (const tier of ['Q1', 'Q2', 'Q3', 'Q4']) {
      for (const result of ['failure', 'cancelled', 'skipped', 'missing']) {
        const needs = structuredClone({ ...alwaysNeeds, ...successNeeds })
        if (result === 'missing') delete needs[job]
        else needs[job].result = result
        const rejected = runScript('scripts/ci/core-test-aggregate.js', [], {
          ...process.env,
          CORE_TEST_NEEDS_JSON: JSON.stringify(needs),
          CORE_TEST_QA_TIER: tier
        })
        assert(rejected.status !== 0, `${tier} aggregate accepted ${job}=${result} with successful tests`)
        assert(rejected.stderr.includes(`required job ${job} result=${result}`), `${tier} lost the guard failure reason`)
      }
    }
  }

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
  const coreGuardBlock = workflow.slice(workflow.indexOf('  guards:'), workflow.indexOf('  standalone-guards:'))
  const serverGuardBlock = workflow.slice(workflow.indexOf('  standalone-guards:'), workflow.indexOf('  stage0-free-smoke:'))
  requireIncludes(coreGuardBlock, 'run: npm run ci:guards:core', 'core guard command')
  const matrixCommands = [...serverGuardBlock.matchAll(/- script: ([^\s]+)/g)].map(match => match[1])
  assert(JSON.stringify(matrixCommands) === JSON.stringify(standaloneCommands),
    'standalone guard matrix must execute every local standalone command exactly once')
  requireIncludes(serverGuardBlock, 'run: npm run "${{ matrix.script }}"', 'standalone matrix command')
  requireIncludes(serverGuardBlock, 'fail-fast: false', 'independent standalone matrix outcomes')
  requireIncludes(serverGuardBlock, 'timeout-minutes: 60', 'bounded server job')
  assert(!coreGuardBlock.includes('run: npm run ci:guards\n'), 'core CI must not repeat the local full aggregate')
  assert(!serverGuardBlock.includes('run: npm run ci:guards'), 'server job must not repeat core guards')
  checkIndependentJobStarts(workflow)
  const strictPluginBlock = workflow.slice(workflow.indexOf('  plugin-matrix:'), workflow.indexOf('  native-plugin-happy-path:'))
  const happyPluginBlock = workflow.slice(workflow.indexOf('  native-plugin-happy-path:'), workflow.indexOf('  test-shards:'))
  requireIncludes(strictPluginBlock, '    name: Plugin matrix (strict)\n', 'stable strict plugin check name')
  for (const [block, command] of [
    [strictPluginBlock, 'npm run -s test:plugins:strict-matrix'],
    [happyPluginBlock, 'npm run -s test:hxhx:native-plugin-happy-path']
  ]) {
    requireIncludes(block, '    timeout-minutes: 40\n', 'unchanged plugin job budget')
    requireIncludes(block, command, 'independent plugin command')
    assert(workflow.split(command).length === 2, `${command} must run exactly once in Core`)
  }
  expectThrow(
    () => checkIndependentJobStarts(workflow.replace(
      '  test-shards:\n    name: Tests / ${{ matrix.label }}\n    runs-on: ubuntu-latest\n    needs: [route]',
      '  test-shards:\n    name: Tests / ${{ matrix.label }}\n    runs-on: ubuntu-latest\n    needs: [route, guards]'
    )),
    'must start after routing',
    'restored guard dependency'
  )
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
  const q2Matrix = workflow.slice(q2MatrixStart, q3HxhxStart)
  const expectedBoundedRows = [
    ['compiler-foundation', 'Compiler foundations and runtime'],
    ['compiler-packaging', 'OCaml packaging and metal profile'],
    ['compiler-focused-1', 'Focused compiler regressions (1/5)'],
    ['compiler-focused-call-arguments', 'Native call arguments and inference'],
    ['compiler-focused-2', 'Focused compiler regressions (2/5)'],
    ['compiler-focused-neko-runtime', 'Neko runtime types and target admission', 60],
    ['compiler-focused-neko-locals', 'Neko local bindings and constructors'],
    ['compiler-focused-3', 'C++ constructor and instance regressions'],
    ['compiler-focused-4', 'C++ arithmetic and control regressions'],
    ['compiler-focused-cpp-closure-storage', 'C++ closures and inherited storage'],
    ['compiler-focused-5', 'C++ runtime type and Map regressions'],
    ['macro-host-integration', 'Macro-host integration'],
    ['target-packages', 'Snapshots and examples']
  ]
  for (const [shard, label, timeoutMinutes = 40] of expectedBoundedRows) {
    requireIncludes(
      q2Matrix,
      `          - shard: ${shard}\n            label: ${label}\n            timeout_minutes: ${timeoutMinutes}`,
      `Core bounded shard ${shard}`
    )
  }
  const sourceRuntimeStep = 'Ensure PHP, Mono and Lua are available for focused runtime tests'
  const sourceRuntimeCondition = "startsWith(matrix.shard, 'compiler-focused-') && matrix.shard != 'compiler-focused-4'"
  requireIncludes(q2Matrix, `      - name: ${sourceRuntimeStep}\n        if: \${{ ${sourceRuntimeCondition} }}`,
    'only C++ arithmetic may omit PHP, Mono and Lua setup')
  const actualSourceRuntimeCondition = q2Matrix.match(
    /- name: Ensure PHP, Mono and Lua are available for focused runtime tests\n        if: \$\{\{ (.+) \}\}/
  )[1]
  for (const shard of plan.shards) {
    const selected = vm.runInNewContext(actualSourceRuntimeCondition, {
      matrix: { shard: shard.id },
      startsWith: (value, prefix) => value.startsWith(prefix)
    })
    const expected = shard.id.startsWith('compiler-focused-') && shard.id !== 'compiler-focused-4'
    assert(selected === expected, `PHP, Mono and Lua setup changed for ${shard.id}`)
  }
  requireIncludes(q2Matrix,
    "      - name: Expose the Neko compiler for focused tests\n        if: ${{ startsWith(matrix.shard, 'compiler-focused-') }}",
    'all focused partitions must retain Neko compiler setup')
  assert(
    (q2Matrix.match(/          - shard: portable\n/g) || []).length === 3,
    'Core workflow must run exactly three portable fixture partitions'
  )
  for (const index of [0, 1, 2]) {
    requireIncludes(
      q2Matrix,
      `          - shard: portable\n            label: Portable fixtures (${index + 1}/3)\n            timeout_minutes: 50\n            portable_shard_index: "${index}"\n            portable_shard_count: "3"\n            portable_jobs: "4"\n            portable_fixture_timeout_seconds: "2100"`,
      `Core portable fixture partition ${index}`
    )
  }
  requireIncludes(q2Matrix, '    timeout-minutes: ${{ matrix.timeout_minutes }}', 'Core test shard timeout budget')
  requireIncludes(q2Matrix, 'PORTABLE_SHARD_INDEX: ${{ matrix.portable_shard_index }}', 'Core portable shard index')
  requireIncludes(q2Matrix, 'PORTABLE_SHARD_COUNT: ${{ matrix.portable_shard_count }}', 'Core portable shard count')
  requireIncludes(q2Matrix, 'PORTABLE_JOBS: ${{ matrix.portable_jobs }}', 'Core portable worker budget')
  requireIncludes(
    q2Matrix,
    'PORTABLE_FIXTURE_TIMEOUT_SECONDS: ${{ matrix.portable_fixture_timeout_seconds }}',
    'Core portable fixture deadline'
  )
  requireIncludes(workflow, '  hxhx-e2e:\n    name: Tests / hxhx target end-to-end', 'Q3 hxhx E2E job')
  const e2eJob = workflow.slice(q3HxhxStart, workflow.indexOf('\n  test:', q3HxhxStart))
  requireIncludes(e2eJob, "needs.route.outputs.run_q3 == 'true'", 'Q3 hxhx E2E condition')
  requireIncludes(e2eJob, '    timeout-minutes: 40', 'Q3 hxhx E2E budget')
  const e2eStepStart = e2eJob.indexOf('      - name: Run hxhx target end-to-end shard\n')
  assert(e2eStepStart >= 0, 'Q3 hxhx E2E step is missing')
  const e2eStep = e2eJob.slice(e2eStepStart)
  requireIncludes(e2eStep, 'HXHX_FORCE_STAGE0: "0"', 'Q3 snapshot compiler selection')
  requireIncludes(e2eStep, 'HXHX_BOOTSTRAP_PREFER_NATIVE: "1"', 'Q3 native bootstrap preference')
  requireIncludes(e2eStep, 'npm run test:ci:shard -- --shard hxhx-targets', 'Q3 hxhx E2E runner')
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
  assert(ciList.stderr.includes('HAXE_FAMILY_HEAVY_RUN:CI_BYPASS'), 'CI shard did not bypass the local lease')
  assert(ciList.stdout.includes('test:hxhx-targets'), 'wrapped shard did not receive its forwarded arguments')

  console.log(`[core-test-shard-fixture-test] commands=${plan.aggregateCommands.length} shards=${plan.shards.length}`)
  console.log('CORE_TEST_SHARD_CONTRACT:PASS')
}

main()
