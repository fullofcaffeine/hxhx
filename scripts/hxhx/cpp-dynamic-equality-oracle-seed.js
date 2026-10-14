#!/usr/bin/env node
// Preserve target-specific observations without reading upstream compiler code.
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')
const source = 'test/oracle/cpp_dynamic_equality_seed'
const output = path.join(root, '.tmp/cpp-dynamic-equality-upstream')
const haxe = process.env.HAXE_BIN || 'haxe'
const payloadOnly = process.argv.slice(2).join(' ') === '--payload-only'
if (process.argv.length > 2 && !payloadOnly) throw new Error('Expected no arguments or --payload-only')
fs.mkdirSync(output, { recursive: true })

function run(command, args, label, timeout) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout,
    env: process.env, maxBuffer: 16 * 1024 * 1024 })
  fs.writeFileSync(path.join(output, `${label}.stdout`), result.stdout || '')
  fs.writeFileSync(path.join(output, `${label}.stderr`), result.stderr || '')
  if (result.error || result.signal || result.status !== 0) {
    throw new Error(`${label} failed: ${result.error || result.signal || result.status}; see ${output}`)
  }
  return result
}

if (run(haxe, ['--version'], 'compiler-version', 10000).stdout.trim() !== '4.3.7') {
  throw new Error('This contract requires Haxe 4.3.7')
}
const libraries = run('haxelib', ['list'], 'libraries', 10000).stdout
if (!/^hxcpp:.*\[4\.3\.2\]/m.test(libraries)) {
  throw new Error('The selected haxelib environment must provide hxcpp 4.3.2')
}
const cases = [
  ...(payloadOnly ? [] : [{ main: 'Main', directory: source, prefix: '', native: 'native' }]),
  { main: 'EnumPayloadProbe', directory: `${source}/enum_payload`, prefix: '', native: 'enum-native' },
  { main: 'FloatTextProbe', directory: `${source}/enum_payload`, prefix: 'float.', native: 'float-native' },
]
for (const fixture of cases) {
  const interpreted = run(haxe, ['-cp', fixture.directory, '-main', fixture.main, '--interp'], `${fixture.main}-eval`, 30000)
  const nativeDirectory = path.join(output, fixture.native)
  run(haxe, ['-cp', fixture.directory, '-main', fixture.main, '-cpp', nativeDirectory,
    '-D', 'HXCPP_COMPILE_THREADS=2'], `${fixture.main}-build`, 300000)
  const native = run(path.join(nativeDirectory, fixture.main), [], `${fixture.main}-cpp`, 30000)
  for (const [target, result] of [['eval', interpreted], ['cpp', native]]) {
    const expected = fs.readFileSync(path.join(root, fixture.directory, `${fixture.prefix}expected.${target}.stdout`), 'utf8')
    if (result.stderr !== '' || result.stdout !== expected) {
      throw new Error(`${fixture.main}/${target} differs from its recorded observations; see ${output}`)
    }
    console.log(`CPP_DYNAMIC_EQUALITY_ORACLE:${fixture.main}:${target}:PASS`)
  }
}
