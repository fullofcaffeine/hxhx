#!/usr/bin/env node

const { violationsInText } = require('./local-path-check')

function assert(condition, message) {
	if (!condition) throw new Error(message)
}

const mac = violationsInText('fixture.md', 'source: /Users/example/project/file.hx')
assert(mac.length === 1 && mac[0].pattern === 'macos_home_path', 'macOS home path must be rejected')

const linux = violationsInText('fixture.md', 'source: /home/example/project/file.hx')
assert(linux.length === 1 && linux[0].pattern === 'linux_home_path', 'Linux home path must be rejected')

const hostedRunner = violationsInText('fixture.md', 'source: /home/runner/work/project/file.hx')
assert(hostedRunner.length === 0, 'GitHub hosted-runner paths remain allowed')

const portable = violationsInText('fixture.md', 'source: <haxe-4.3.7-std>/StringBuf.hx')
assert(portable.length === 0, 'repository-independent placeholders must remain allowed')

console.log('[local-path-check-fixture-test] ok')
