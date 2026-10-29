#!/usr/bin/env node
// Exercise the memory primitive independently of compiler-generated root plans.
const { spawnSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-managed-heap-'))
const compiler = process.env.CXX || 'clang++'
const common = ['-std=c++17', '-Wall', '-Wextra', '-Werror', '-I', path.join(root, 'packages/hxhx-core/runtime/cpp')]

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 60000 })
  if (result.error) throw result.error
  if (result.signal) throw new Error(`${command} terminated by ${result.signal}`)
  return result
}

function successful(command, args) {
  const result = run(command, args)
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})\n${result.stdout}${result.stderr}`)
  return result.stdout
}

try {
  const fixtures = [
    ['ManagedHeapTest', 'CPP_MANAGED_HEAP'],
    ['ManagedValueTest', 'CPP_MANAGED_VALUE'],
    ['ManagedEnumTest', 'CPP_MANAGED_ENUM'],
    ['ManagedAllocationFailureTest', 'CPP_MANAGED_ALLOCATION_FAILURE'],
    ['ManagedStaticRootTest', 'CPP_MANAGED_STATIC_ROOT'],
    ['ManagedCallableTest', 'CPP_MANAGED_CALLABLE'],
    ['ManagedStackTest', 'CPP_MANAGED_STACK']
  ]
  const requested = process.argv.slice(2)
  if (requested.length > 1 || (requested.length === 1 && !fixtures.some(([name]) => name === requested[0]))) {
    throw new Error(`expected zero arguments or one fixture: ${fixtures.map(([name]) => name).join(', ')}`)
  }
  const selected = requested.length === 0 ? fixtures : fixtures.filter(([name]) => name === requested[0])
  for (const [fixture, marker] of selected) {
    for (const optimization of ['-O0', '-O2']) {
      const executable = path.join(temporary, `${fixture}${optimization}`)
      successful(compiler, [...common, optimization, '-g', '-fno-omit-frame-pointer', '-fsanitize=address,undefined',
        `test/cpp_managed_heap/${fixture}.cpp`, '-o', executable])
      const output = successful(executable, [])
      if (output !== `${marker}:PASS\n`) throw new Error(`unexpected runtime output: ${JSON.stringify(output)}`)
      console.log(`${marker}:${optimization}:PASS`)
    }
  }
  if (requested.length === 0 || requested[0] === 'ManagedHeapTest') {
    const rejected = run(compiler, [...common, '-fsyntax-only', 'test/cpp_managed_heap/MissingTrace.cpp'])
    if (rejected.status === 0 || !/Trace/.test(rejected.stderr) || !/UnknownPayload/.test(rejected.stderr)) {
      throw new Error(`missing tracing declaration was not rejected as expected\n${rejected.stderr}`)
    }
    console.log('CPP_MANAGED_HEAP:MISSING_TRACE_REJECTED:PASS')
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}
