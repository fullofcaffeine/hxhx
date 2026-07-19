#!/usr/bin/env node
/**
 * Keeps the historical `Tests` check fail-closed after its work is sharded.
 * GitHub supplies every prerequisite result through the `needs` context.
 */

const { evaluateAggregateResults, loadPlan } = require('./core-test-shards')

function fail(message) {
  console.error(`[core-test-aggregate] ERROR: ${message}`)
  process.exit(1)
}

function main() {
  let plan
  let needs
  try {
    plan = loadPlan()
    needs = JSON.parse(process.env.CORE_TEST_NEEDS_JSON || '')
  } catch (error) {
    fail(error.message)
  }

  const failures = evaluateAggregateResults(plan.manifest.aggregateJobs, needs)
  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(`[core-test-aggregate] required job ${failure.job} result=${failure.result}`)
    }
    fail('one or more required Core Tests jobs did not succeed')
  }

  console.log(`[core-test-aggregate] PASS jobs=${plan.manifest.aggregateJobs.length} commands=${plan.aggregateCommands.length}`)
  console.log('CORE_TESTS_AGGREGATE:PASS')
}

main()
