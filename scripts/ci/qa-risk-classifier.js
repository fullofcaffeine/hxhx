#!/usr/bin/env node
/**
 * Classifies one immutable change set into the Q0-Q4 QA tiers.
 *
 * The classifier is deliberately independent of GitHub APIs. Callers provide
 * an event name and a newline-delimited changed-path file, which makes the
 * result reproducible locally and in every CI host. Unknown code paths fail
 * safe to the bounded hxhx canary instead of silently skipping it.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const POLICY_PATH = path.join(__dirname, 'qa-risk-policy.json')
const RESULT_SCHEMA = 'hxhx.qa-risk-classification.v2'
const TIERS = ['Q0', 'Q1', 'Q2', 'Q3', 'Q4']

function invariant(condition, message) {
  if (!condition) throw new Error(message)
}

function tierIndex(tier) {
  const index = TIERS.indexOf(tier)
  invariant(index !== -1, `unknown QA tier: ${tier}`)
  return index
}

function maxTier(...tiers) {
  return tiers.reduce((highest, tier) => (
    tierIndex(tier) > tierIndex(highest) ? tier : highest
  ), 'Q0')
}

function normalizeChangedPath(value) {
  return value.trim().replaceAll('\\', '/').replace(/^\.\//, '')
}

function loadPolicy(policyPath = POLICY_PATH) {
  const raw = fs.readFileSync(policyPath, 'utf8')
  const policy = JSON.parse(raw)
  invariant(policy.schema === 'hxhx.qa-risk-policy.v1', `unexpected policy schema: ${policy.schema}`)
  tierIndex(policy.defaultUnknownTier)
  invariant(policy.eventMinimums && typeof policy.eventMinimums === 'object', 'eventMinimums must be an object')
  invariant(
    Array.isArray(policy.q0WorkflowIgnorePatterns) && policy.q0WorkflowIgnorePatterns.length > 0,
    'q0WorkflowIgnorePatterns must be a non-empty array'
  )
  invariant(
    Array.isArray(policy.q1HxhxWorkflowIgnorePatterns) && policy.q1HxhxWorkflowIgnorePatterns.length > 0,
    'q1HxhxWorkflowIgnorePatterns must be a non-empty array'
  )
  invariant(Array.isArray(policy.rules) && policy.rules.length > 0, 'rules must be a non-empty array')

  const ids = new Set()
  for (const rule of policy.rules) {
    invariant(rule && typeof rule.id === 'string' && rule.id !== '', 'every rule needs an id')
    invariant(!ids.has(rule.id), `duplicate rule id: ${rule.id}`)
    ids.add(rule.id)
    tierIndex(rule.tier)
    invariant(
      rule.terminal === undefined || typeof rule.terminal === 'boolean',
      `rule ${rule.id} terminal must be boolean when present`
    )
    invariant(typeof rule.description === 'string' && rule.description !== '', `rule ${rule.id} needs a description`)
    const matchers = ['exact', 'prefixes', 'suffixes']
      .flatMap(field => Array.isArray(rule[field]) ? rule[field] : [])
    invariant(matchers.length > 0, `rule ${rule.id} needs at least one path matcher`)
  }
  for (const tier of Object.values(policy.eventMinimums)) tierIndex(tier)

  return {
    policy,
    policyDigest: crypto.createHash('sha256').update(raw).digest('hex')
  }
}

function ruleMatches(rule, changedPath) {
  return (rule.exact || []).includes(changedPath)
    || (rule.prefixes || []).some(prefix => changedPath.startsWith(prefix))
    || (rule.suffixes || []).some(suffix => changedPath.endsWith(suffix))
}

function classify(options, loaded = loadPolicy()) {
  const event = String(options.event || 'local').trim()
  const requestedTier = options.requestedTier && options.requestedTier !== 'auto'
    ? String(options.requestedTier).toUpperCase()
    : 'Q0'
  tierIndex(requestedTier)

  const changedPaths = [...new Set((options.changedPaths || [])
    .map(normalizeChangedPath)
    .filter(Boolean))].sort()
  const matches = []
  const unknownPaths = []
  let pathTier = 'Q0'

  for (const changedPath of changedPaths) {
    const matchedRules = loaded.policy.rules.filter(rule => ruleMatches(rule, changedPath))
    if (matchedRules.length === 0) {
      unknownPaths.push(changedPath)
      pathTier = maxTier(pathTier, loaded.policy.defaultUnknownTier)
      continue
    }
    // A terminal rule owns the complete path classification. Documentation is
    // therefore Q0 even when its README lives below a compiler/source prefix.
    const terminalRules = matchedRules.filter(rule => rule.terminal === true)
    const effectiveRules = terminalRules.length > 0 ? terminalRules : matchedRules
    const matchedTier = effectiveRules.reduce((tier, rule) => maxTier(tier, rule.tier), 'Q0')
    pathTier = maxTier(pathTier, matchedTier)
    matches.push({
      path: changedPath,
      tier: matchedTier,
      rules: effectiveRules.map(rule => rule.id).sort()
    })
  }

  const eventMinimum = loaded.policy.eventMinimums[event] || 'Q0'
  const emptyChangeMinimum = changedPaths.length === 0 && ['push', 'pull_request'].includes(event) ? 'Q3' : 'Q0'
  const tier = maxTier(pathTier, eventMinimum, requestedTier, emptyChangeMinimum)
  const index = tierIndex(tier)
  const reasons = []
  if (tierIndex(pathTier) > 0) reasons.push(`changed paths require ${pathTier}`)
  if (tierIndex(eventMinimum) > 0) reasons.push(`${event} requires at least ${eventMinimum}`)
  if (tierIndex(requestedTier) > 0) reasons.push(`manual request requires at least ${requestedTier}`)
  if (tierIndex(emptyChangeMinimum) > 0) reasons.push(`missing ${event} change inventory escalates to ${emptyChangeMinimum}`)
  if (unknownPaths.length > 0) reasons.push(`${unknownPaths.length} unknown path(s) fail safe to ${loaded.policy.defaultUnknownTier}`)
  if (reasons.length === 0) reasons.push('all changed paths are Q0 documentation or tracking records')

  return {
    schema: RESULT_SCHEMA,
    policySchema: loaded.policy.schema,
    policySha256: loaded.policyDigest,
    producerSha: options.producerSha || null,
    event,
    requestedTier,
    tier,
    changedPathCount: changedPaths.length,
    changedPaths,
    matches,
    unknownPaths,
    runs: {
      routingAggregate: true,
      focusedTarget: index >= tierIndex('Q1'),
      standalonePackage: index >= tierIndex('Q1'),
      hxhxCanary: index >= tierIndex('Q2'),
      largeHxhxConsumer: index >= tierIndex('Q3'),
      authenticCompilerPromotion: index >= tierIndex('Q3'),
      hxhxReleaseEvidence: index >= tierIndex('Q4')
    },
    reasons
  }
}

function parseArgs(argv) {
  const options = { requestedTier: 'auto' }
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    const next = () => {
      index += 1
      invariant(index < argv.length, `${argument} requires a value`)
      return argv[index]
    }
    if (argument === '--event') options.event = next()
    else if (argument === '--paths-file') options.pathsFile = next()
    else if (argument === '--requested-tier') options.requestedTier = next()
    else if (argument === '--producer-sha') options.producerSha = next()
    else if (argument === '--inventory-file') options.inventoryFile = next()
    else if (argument === '--repository') options.repository = next()
    else if (argument === '--workflow') options.workflow = next()
    else if (argument === '--run-id') options.runId = next()
    else if (argument === '--run-attempt') options.runAttempt = next()
    else if (argument === '--output') options.output = next()
    else if (argument === '--github-output') options.githubOutput = next()
    else throw new Error(`unknown argument: ${argument}`)
  }
  return options
}

function loadInventory(filePath, changedPaths, producerSha) {
  if (!filePath) return null
  const inventory = JSON.parse(fs.readFileSync(filePath, 'utf8'))
  invariant(inventory.schema === 'hxhx.qa-risk-change-inventory.v1', `unexpected inventory schema: ${inventory.schema}`)
  invariant(inventory.headSha === producerSha, 'inventory head does not match the QA producer')
  const normalized = [...new Set(changedPaths.map(normalizeChangedPath).filter(Boolean))].sort()
  const rendered = normalized.length === 0 ? '' : `${normalized.join('\n')}\n`
  const digest = crypto.createHash('sha256').update(rendered).digest('hex')
  invariant(inventory.changedPathCount === normalized.length, 'inventory changed-path count does not match its path file')
  invariant(inventory.changedPathsSha256 === digest, 'inventory changed-path digest does not match its path file')
  return inventory
}

function sourceIdentity(options) {
  if (!options.repository && !options.workflow && !options.runId && !options.runAttempt) return null
  const runId = Number(options.runId)
  const runAttempt = Number(options.runAttempt)
  invariant(options.repository, '--repository is required with a source identity')
  invariant(options.workflow, '--workflow is required with a source identity')
  invariant(Number.isInteger(runId) && runId > 0, '--run-id must be a positive integer')
  invariant(Number.isInteger(runAttempt) && runAttempt > 0, '--run-attempt must be a positive integer')
  return { repository: options.repository, workflow: options.workflow, runId, runAttempt }
}

function writeGithubOutput(filePath, result) {
  const values = {
    tier: result.tier,
    run_q1: result.runs.standalonePackage,
    run_q2: result.runs.hxhxCanary,
    run_q3: result.runs.largeHxhxConsumer,
    run_authentic_compiler: result.runs.authenticCompilerPromotion,
    run_q4: result.runs.hxhxReleaseEvidence,
    policy_sha256: result.policySha256,
    reason: result.reasons.join('; ')
  }
  fs.appendFileSync(filePath, `${Object.entries(values).map(([key, value]) => `${key}=${value}`).join('\n')}\n`)
}

function main() {
  const options = parseArgs(process.argv.slice(2))
  const changedPaths = options.pathsFile
    ? fs.readFileSync(options.pathsFile, 'utf8').split(/\r?\n/)
    : []
  const result = classify({ ...options, changedPaths })
  result.inventory = loadInventory(options.inventoryFile, changedPaths, result.producerSha)
  result.source = sourceIdentity(options)
  const rendered = `${JSON.stringify(result, null, 2)}\n`
  if (options.output) {
    fs.mkdirSync(path.dirname(options.output), { recursive: true })
    fs.writeFileSync(options.output, rendered)
  }
  if (options.githubOutput) writeGithubOutput(options.githubOutput, result)
  process.stdout.write(rendered)
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[qa-risk-classifier] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  POLICY_PATH,
  RESULT_SCHEMA,
  TIERS,
  classify,
  loadInventory,
  loadPolicy,
  maxTier,
  normalizeChangedPath,
  parseArgs,
  ruleMatches,
  sourceIdentity,
  tierIndex,
  writeGithubOutput
}
