#!/usr/bin/env node

const SUITES = {
  misc: {
    marker: 'FULL1_SUITE_MISC:PASS',
    cwd: 'vendor/haxe/tests/misc',
    entryHxml: 'compile.hxml',
  },
  server: {
    marker: 'FULL1_SUITE_SERVER:PASS',
    cwd: 'vendor/haxe/tests/server',
    entryHxml: 'run.hxml',
  },
  threads: {
    marker: 'FULL1_SUITE_THREADS:PASS',
    cwd: 'vendor/haxe/tests/threads',
    entryHxml: 'build.hxml',
  },
  optimization: {
    marker: 'FULL1_SUITE_OPTIMIZATION:PASS',
    cwd: 'vendor/haxe/tests/optimization',
    entryHxml: 'run.hxml',
  },
  display: {
    marker: 'FULL1_SUITE_DISPLAY:PASS',
    cwd: 'vendor/haxe/tests/display',
    entryHxml: 'build.hxml',
  },
}

const SUITE_HAXELIB_DEPS = {
  server: [
    { name: 'utest', repo: 'https://github.com/haxe-utest/utest', ref: 'a94f8812e8786f2b5fec52ce9f26927591d26327' },
    { name: 'haxeserver', repo: 'https://github.com/Simn/haxeserver' },
    { name: 'hxnodejs', repo: 'https://github.com/HaxeFoundation/hxnodejs' },
  ],
  display: [
    { name: 'utest', repo: 'https://github.com/haxe-utest/utest', ref: 'a94f8812e8786f2b5fec52ce9f26927591d26327' },
    { name: 'haxeserver', repo: 'https://github.com/Simn/haxeserver' },
  ],
  threads: [
    { name: 'utest', repo: 'https://github.com/haxe-utest/utest', ref: 'a94f8812e8786f2b5fec52ce9f26927591d26327' },
  ],
}

function listUniqueSuiteDependencies(suites) {
  const unique = new Map()
  for (const suite of suites) {
    const deps = SUITE_HAXELIB_DEPS[suite] || []
    for (const dep of deps) {
      const key = `${dep.name}|${dep.repo}|${dep.ref || ''}`
      if (!unique.has(key)) {
        unique.set(key, dep)
      }
    }
  }
  return Array.from(unique.values())
}

module.exports = {
  SUITES,
  SUITE_HAXELIB_DEPS,
  listUniqueSuiteDependencies,
}
