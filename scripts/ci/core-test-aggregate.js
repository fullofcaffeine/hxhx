#!/usr/bin/env node
/**
 * Keeps the historical `Tests` check fail-closed after its work is sharded and
 * risk-routed. GitHub supplies every prerequisite result through the `needs`
 * context; the shard manifest is the only authority for tier-approved skips.
 */

const { QA_TIERS, evaluateAggregateResults, jobsRequiredAtTier, loadPlan } = require('./core-test-shards')

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

  const requiredJobs = new Set(jobsRequiredAtTier(plan.manifest, tier))
  const allowSkipped = plan.manifest.aggregateJobs.filter(job => !requiredJobs.has(job))
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
    `[core-test-aggregate] PASS tier=${tier} always=${alwaysRequiredJobs.length} jobs=${plan.manifest.aggregateJobs.length} required=${requiredJobs.size} skipped=${allowSkipped.length} commands=${plan.aggregateCommands.length}`
  )
  console.log('CORE_TESTS_AGGREGATE:PASS')
}

main()
