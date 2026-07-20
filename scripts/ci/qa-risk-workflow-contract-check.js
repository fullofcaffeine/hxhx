#!/usr/bin/env node
/**
 * Keeps cheap Q0/Q1 routing consistent across automatic GitHub workflows.
 *
 * Core CI intentionally remains present for every push and pull request so its
 * stable aggregate can explain the route. Other broad automatic workflows must
 * ignore the exact documentation/tracking patterns owned by the QA policy, and
 * hxhx-only workflows must also ignore standalone reflaxe.ocaml Q1 surfaces.
 */

const fs = require('fs')
const path = require('path')

const workflowRoot = '.github/workflows'
const coreWorkflow = 'ci.yml'
const q0IgnoredWorkflows = new Set([
  'codeql.yml',
  'gate1-lite.yml',
  'gate2-lite.yml',
  'gate3-builtin.yml',
  'hxhx-kpi-report.yml',
  'js-oracle-smoke.yml',
  'm14-perf-report.yml',
  'semantic-diff.yml',
  'stdlib-portable-lite.yml'
])
const q1HxhxIgnoredWorkflows = new Set([
  'gate1-lite.yml',
  'gate3-builtin.yml',
  'hxhx-kpi-report.yml',
  'js-oracle-smoke.yml'
])

function fail(message) {
  console.error(`[qa-risk-workflow-contract-check] ERROR: ${message}`)
  process.exitCode = 1
}

function eventBlock(text, event) {
  const lines = text.split(/\r?\n/)
  const start = lines.findIndex(line => line === `  ${event}:`)
  if (start === -1) return null
  let end = start + 1
  while (end < lines.length && !/^  [A-Za-z0-9_-]+:/.test(lines[end])) end += 1
  return lines.slice(start, end).join('\n')
}

function hasPathFilter(block) {
  return /\n    paths(?:-ignore)?:\s*(?:\n|\[)/.test(block)
}

function main() {
  const policy = JSON.parse(fs.readFileSync('scripts/ci/qa-risk-policy.json', 'utf8'))
  const ciGates = fs.readFileSync('docs/00-project/CI_GATES.md', 'utf8')
  const q0Patterns = policy.q0WorkflowIgnorePatterns
  const q1HxhxPatterns = policy.q1HxhxWorkflowIgnorePatterns
  if (!Array.isArray(q0Patterns) || q0Patterns.length === 0) {
    fail('policy.q0WorkflowIgnorePatterns must be a non-empty array')
    return
  }
  if (!Array.isArray(q1HxhxPatterns) || q1HxhxPatterns.length === 0) {
    fail('policy.q1HxhxWorkflowIgnorePatterns must be a non-empty array')
    return
  }
  for (const unsafeBroadPattern of ['examples/**', 'packages/reflaxe.ocaml/examples/**']) {
    if (q1HxhxPatterns.includes(unsafeBroadPattern)) {
      fail(`Q1 hxhx ignore patterns must not hide hxhx-specific examples via ${unsafeBroadPattern}`)
    }
  }
  for (const snippet of [
    '### Risk-routed PR cost',
    'scripts/ci/qa-risk-policy.json',
    'scripts/ci/qa-risk-classifier.js',
    'scripts/ci/qa-risk-workflow-contract-check.js',
    'haxe_ocaml-bxwut'
  ]) {
    if (!ciGates.includes(snippet)) fail(`docs/00-project/CI_GATES.md must include ${snippet}`)
  }

  const workflowFiles = fs.readdirSync(workflowRoot).filter(file => file.endsWith('.yml')).sort()
  for (const workflow of q0IgnoredWorkflows) {
    if (!workflowFiles.includes(workflow)) {
      fail(`missing Q0-routed workflow: ${workflow}`)
      continue
    }
    const text = fs.readFileSync(path.join(workflowRoot, workflow), 'utf8')
    const patterns = q1HxhxIgnoredWorkflows.has(workflow)
      ? [...q0Patterns, ...q1HxhxPatterns]
      : q0Patterns
    for (const event of ['push', 'pull_request']) {
      const block = eventBlock(text, event)
      if (!block) {
        fail(`${workflow} must retain its ${event} trigger`)
        continue
      }
      if (!block.includes('\n    paths-ignore:')) {
        fail(`${workflow} ${event} must define paths-ignore`)
      }
      for (const pattern of patterns) {
        if (!block.includes(`      - '${pattern}'`)) {
          fail(`${workflow} ${event} is missing Q0 ignore pattern ${pattern}`)
        }
      }
    }
  }

  for (const workflow of workflowFiles) {
    const text = fs.readFileSync(path.join(workflowRoot, workflow), 'utf8')
    for (const event of ['push', 'pull_request']) {
      const block = eventBlock(text, event)
      if (!block || hasPathFilter(block)) continue
      if (workflow === coreWorkflow) {
        if (!text.includes('  route:\n    name: QA risk route')) {
          fail(`${coreWorkflow} must keep the cheap always-run QA route`)
        }
        continue
      }
      fail(`${workflow} has an unclassified broad ${event} trigger`)
    }
  }

  if (process.exitCode) return
  console.log(
    `QA_RISK_WORKFLOW_CONTRACT:PASS q0_ignored=${q0IgnoredWorkflows.size} q1_hxhx_ignored=${q1HxhxIgnoredWorkflows.size} q0_patterns=${q0Patterns.length} q1_patterns=${q1HxhxPatterns.length}`
  )
}

main()
