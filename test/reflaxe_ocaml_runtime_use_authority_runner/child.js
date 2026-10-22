/** Disposable process tree owned and terminated by the runtime-use runner fixture. */
'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')
const { spawn } = require('node:child_process')
const [role, readyPath, startupDelay] = process.argv.slice(2)
assert.ok(role === 'parent' || role === 'child')
assert.ok(typeof readyPath === 'string' && readyPath.length > 0)
assert.ok(startupDelay === 'never' || /^(0|350)$/.test(startupDelay))

if (role === 'parent') {
	process.on('SIGTERM', () => {})
	const child = spawn(process.execPath, [__filename, 'child', readyPath, startupDelay], {
		stdio: ['ignore', 'ignore', 'ignore', 'ipc'],
	})
	fs.writeFileSync(readyPath + '.created', String(child.pid))
	child.once('message', message => {
		assert.equal(message, 'ready')
		// Atomic publication lets the watcher read only a complete readiness record.
		fs.writeFileSync(readyPath + '.pending', JSON.stringify({ parent: process.pid, child: child.pid }))
		fs.renameSync(readyPath + '.pending', readyPath)
	})
} else if (startupDelay !== 'never') {
	setTimeout(() => {
		process.on('SIGTERM', () => {})
		process.send('ready')
	}, Number(startupDelay))
}
setInterval(() => {}, 1000)
