#!/usr/bin/env node
/** Proves controlled edit helpers and local/external workspace isolation. */
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { changedFiles, replaceExactlyOnce } = require('./reflaxe-ocaml-iteration-perf')
const { cleanupPerformanceContext, isolatedScenarioDirectory } = require('./reflaxe-ocaml-perf-platform')

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-iteration-fixture-'))

function expectFailure(callback, pattern) {
	assert.throws(callback, pattern)
}

try {
	assert.strictEqual(replaceExactlyOnce('before value after', 'value', 'changed', 'fixture'), 'before changed after')
	expectFailure(() => replaceExactlyOnce('no marker', 'value', 'changed', 'fixture'), /exactly one/)
	expectFailure(() => replaceExactlyOnce('value and value', 'value', 'changed', 'fixture'), /exactly one/)
	assert.deepStrictEqual(changedFiles(new Map([['a', '1'], ['b', '2']]), new Map([['a', '1'], ['b', '3'], ['c', '4']])), ['b', 'c'])

	const repoRoot = path.join(tempRoot, 'repo')
	const exampleDirectory = path.join(repoRoot, 'example')
	fs.mkdirSync(exampleDirectory, { recursive: true })
	fs.writeFileSync(path.join(exampleDirectory, 'Main.hx'), 'class Main {}\n')
	const localContext = {
		repoRoot,
		workRoot: null,
		replacements: [repoRoot],
		temporaryRoots: []
	}
	const localCopy = isolatedScenarioDirectory({id: 'local-copy', exampleDir: 'example'}, localContext)
	assert(localCopy.startsWith(path.join(repoRoot, '.tmp') + path.sep))
	assert.strictEqual(fs.readFileSync(path.join(localCopy, 'Main.hx'), 'utf8'), 'class Main {}\n')
	assert.strictEqual(localContext.temporaryRoots.length, 1)
	cleanupPerformanceContext(localContext)
	assert(!fs.existsSync(localContext.temporaryRoots[0]))

	const externalRoot = path.join(tempRoot, 'external')
	fs.mkdirSync(externalRoot)
	const externalContext = {
		repoRoot,
		workRoot: externalRoot,
		replacements: [repoRoot, externalRoot],
		temporaryRoots: []
	}
	const externalCopy = isolatedScenarioDirectory({id: 'external-copy', exampleDir: 'example'}, externalContext)
	assert.strictEqual(path.dirname(externalCopy), externalRoot)
	cleanupPerformanceContext(externalContext)
	assert(!fs.existsSync(externalRoot))

	console.log('REFLAXE_OCAML_ITERATION_PERF_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, { recursive: true, force: true })
}
