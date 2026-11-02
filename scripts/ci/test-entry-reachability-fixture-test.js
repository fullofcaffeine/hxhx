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

// A wrapper counts as reachable only when CI runs the same command. An
// environment variable or an extra argument selects a variant CI never runs.
const filtered = { 'file:test/filtered_test.hxml': exception }
result = evaluate(writeRepo(baseFiles({
  ...scripts,
  'test:smoke-variant': 'HXHX_GROUP=extra haxe test/smoke_test.hxml',
  'test:smoke-define': 'haxe test/smoke_test.hxml -D extra',
  'test:smoke-copy': 'haxe test/smoke_test.hxml'
}, filtered)))
assert.ok(result.unreachable.includes('script:test:smoke-variant'), 'an environment variant must stay unreachable')
assert.ok(result.unreachable.includes('script:test:smoke-define'), 'an argument variant must stay unreachable')
assert.ok(!result.unreachable.includes('script:test:smoke-copy'), 'an identical command must count as reachable')

// A new unlisted script that only runs a listed script's files still needs
// its own entry; only files share an exception.
result = evaluate(writeRepo(baseFiles({
  ...scripts,
  'test:manual': 'haxe test/filtered_test.hxml',
  'test:manual-copy': 'haxe test/filtered_test.hxml'
}, { 'script:test:manual': exception })))
assert.ok(result.errors.some(error => error.includes('script:test:manual-copy')), 'an unlisted script must not share an exception')

// An .hxml file's main class is followed: here it starts another test build.
result = evaluate(writeRepo({
  ...baseFiles({ ...scripts, 'test:aggregate': 'haxe test/main_test.hxml' }, filtered),
  'test/main_test.hxml': '-cp test\n-main MainTest\n--interp\n',
  'test/MainTest.hx': 'class MainTest { static function main() Sys.command("haxe", ["test/aggregate_test.hxml"]); }\n'
}))
assert.ok(!result.unreachable.includes('file:test/aggregate_test.hxml'), 'the main class reference must be followed')

// A portable fixture is reachable only with test:portable and a build.hxml.
const portable = {
  'test/portable/fixtures/with_build/build.hxml': '--interp\n',
  'test/portable/fixtures/without_build/Main.hx': 'class Main {}\n',
  'scripts/test-portable.sh': 'true\n'
}
result = evaluate(writeRepo({
  ...baseFiles({ ...scripts, test: 'npm run test:aggregate && npm run test:portable', 'test:portable': 'bash scripts/test-portable.sh' }, filtered),
  ...portable
}))
assert.ok(!result.unreachable.includes('fixture:test/portable/fixtures/with_build'))
assert.ok(result.unreachable.includes('fixture:test/portable/fixtures/without_build'))

// `paths-ignore:` filters are not references; matrix list items are.
const matrixRepo = baseFiles({ ...scripts, 'test:matrix-item': 'haxe test/filtered_test.hxml' }, {})
matrixRepo['.github/workflows/ci.yml'] = [
  'on:',
  '  pull_request:',
  '    paths-ignore:',
  '      - test/filtered_test.hxml',
  'jobs:',
  '  matrix:',
  '    strategy:',
  '      matrix:',
  '        script:',
  '          - test:matrix-item',
  '    steps:',
  '      - run: npm run test:smoke',
  '      - run: node scripts/ci/direct-test.js'
].join('\n')
result = evaluate(writeRepo(matrixRepo))
assert.deepStrictEqual(result.unreachable, [], 'a matrix list item must be reachable through its script')

// An exception needs a reason and a bead id.
assert.throws(
  () => evaluate(writeRepo(baseFiles(scripts, { 'file:test/filtered_test.hxml': { reason: 'x' } }))),
  /needs an owning bead id/
)

console.log('TEST_ENTRY_REACHABILITY_FIXTURE:PASS')
