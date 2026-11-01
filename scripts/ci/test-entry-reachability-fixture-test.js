#!/usr/bin/env node
/** Checks test-entry-reachability.js against small temporary repositories. */

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { evaluate, SCHEMA } = require('./test-entry-reachability')

function writeRepo(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'test-entry-reachability-'))
  for (const [relativePath, content] of Object.entries(files)) {
    const absolute = path.join(root, relativePath)
    fs.mkdirSync(path.dirname(absolute), { recursive: true })
    fs.writeFileSync(absolute, typeof content === 'string' ? content : JSON.stringify(content, null, 2))
  }
  return root
}

function baseFiles(scripts, exceptions = {}) {
  return {
    'package.json': { scripts },
    'scripts/ci/test-entry-reachability.json': { schema: SCHEMA, unreachable: exceptions },
    '.github/workflows/ci.yml': [
      'on:',
      '  push:',
      '    paths:',
      '      - test/filtered_test.hxml',
      'jobs:',
      '  smoke:',
      '    steps:',
      '      - run: npm run test:smoke',
      '      - run: node scripts/ci/direct-test.js'
    ].join('\n'),
    'test/aggregate_test.hxml': '--interp\n',
    'test/smoke_test.hxml': '--interp\n',
    'test/filtered_test.hxml': '--interp\n',
    'test/runner_owned_test.hxml': '--interp\n',
    'scripts/ci/direct-test.js': "require('./helper')\n",
    'scripts/ci/helper.js': "spawn('haxe', ['test/runner_owned_test.hxml'])\n"
  }
}

const scripts = {
  test: 'npm run test:aggregate',
  'test:aggregate': 'haxe test/aggregate_test.hxml',
  'test:smoke': 'haxe test/smoke_test.hxml',
  'test:direct': 'node scripts/ci/direct-test.js'
}

// Aggregate, workflow, transitive file, and covered-wrapper references are
// reachable. A workflow `paths:` trigger filter is not a reference.
let result = evaluate(writeRepo(baseFiles(scripts)))
assert.deepStrictEqual(result.unreachable, ['file:test/filtered_test.hxml'])
assert.ok(result.errors.some(error => error.includes('file:test/filtered_test.hxml')), 'an unlisted unreachable test must fail')

// A listed exception passes; a stale exception fails.
const exception = { reason: 'manual lane', bead: 'haxe_ocaml-k86ww' }
result = evaluate(writeRepo(baseFiles(scripts, { 'file:test/filtered_test.hxml': exception })))
assert.deepStrictEqual(result.errors, [])
result = evaluate(writeRepo(baseFiles(scripts, {
  'file:test/filtered_test.hxml': exception,
  'script:test:smoke': exception,
  'file:test/gone_test.hxml': exception
})))
assert.ok(result.errors.some(error => error.includes('script:test:smoke, which CI now reaches')))
assert.ok(result.errors.some(error => error.includes('file:test/gone_test.hxml, which no longer exists')))

// A file that only a listed script runs shares that script's exception.
result = evaluate(writeRepo({
  ...baseFiles({ ...scripts, 'test:manual': 'haxe test/filtered_test.hxml' }, { 'script:test:manual': exception })
}))
assert.deepStrictEqual(result.errors, [])

// A script that runs a missing test file fails even when listed.
result = evaluate(writeRepo(baseFiles(
  { ...scripts, 'test:dead': 'haxe test/missing_test.hxml' },
  { 'file:test/filtered_test.hxml': exception, 'script:test:dead': exception }
)))
assert.ok(result.errors.some(error => error.includes('test:dead runs test/missing_test.hxml, which does not exist')))

// An exception needs a reason and a bead id.
assert.throws(
  () => evaluate(writeRepo(baseFiles(scripts, { 'file:test/filtered_test.hxml': { reason: 'x' } }))),
  /needs an owning bead id/
)

console.log('TEST_ENTRY_REACHABILITY_FIXTURE:PASS')
