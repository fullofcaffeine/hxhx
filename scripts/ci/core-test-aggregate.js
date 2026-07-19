#!/usr/bin/env node
/**
 * Keeps the historical `Tests` check fail-closed after its work is sharded.
 * GitHub supplies every prerequisite result through the `needs` context.
 */

const { evaluateAggregateResults, loadPlan } = require('./core-test-shards')

const QA_TIERS = ['Q0', 'Q1', 'Q2', 'Q3', 'Q4']
const alwaysRequiredJobs = ['route', 'secret-scan']

function fail(message) {
  console.error(`[core-test-aggregate] ERROR: ${message}`)
  process.exit(1)
}

function main() {
  let plan
  let needs
  let tier
  try {
    plan = loadPlan()
    needs = JSON.parse(process.env.CORE_TEST_NEEDS_JSON || '')
    tier = process.env.CORE_TEST_QA_TIER || ''
    if (!QA_TIERS.includes(tier)) throw new Error(`CORE_TEST_QA_TIER must be one of ${QA_TIERS.join(', ')}`)
  } catch (error) {
    fail(error.message)
  }

  const allowSkipped = tier === 'Q0'
    ? plan.manifest.aggregateJobs
    : tier === 'Q1'
      ? plan.manifest.aggregateJobs.filter(job => job !== 'guards')
      : []
  const failures = [
    ...evaluateAggregateResults(alwaysRequiredJobs, needs),
    ...evaluateAggregateResults(plan.manifest.aggregateJobs, needs, { allowSkipped })
  ]
  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(`[core-test-aggregate] required job ${failure.job} result=${failure.result}`)
    }
    fail('one or more required Core Tests jobs did not succeed')
  }

  console.log(
    `[core-test-aggregate] PASS tier=${tier} always=${alwaysRequiredJobs.length} jobs=${plan.manifest.aggregateJobs.length} skipped=${allowSkipped.length} commands=${plan.aggregateCommands.length}`
  )
  console.log('CORE_TESTS_AGGREGATE:PASS')
}

main()
