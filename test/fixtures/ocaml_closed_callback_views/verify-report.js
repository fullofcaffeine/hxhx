#!/usr/bin/env node
/** Exercise the public inspector on real callback output and deliberately corrupted copies. */
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const {execFile} = require('node:child_process')

const root = path.resolve(__dirname, '../../..')
const output = path.resolve(root, process.argv[2])
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-callback-report-'))
const lowering = JSON.parse(fs.readFileSync(path.join(output, 'ocaml_lowering_report.json'), 'utf8'))
const inspector = process.argv[3] ? path.resolve(process.argv[3]) : path.join(temporary, 'inspect.n')

function run(command, args) {
	return new Promise((resolve, reject) => {
		execFile(command, args, {cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 50 * 1024 * 1024}, (error, stdout, stderr) => {
			if (error && (error.killed || typeof error.code !== 'number')) return reject(error)
			resolve({status: error ? error.code : 0, stdout, stderr})
		})
	})
}

async function main() {
	try {
		assert.equal(lowering.schemaVersion, 93)
		assert.equal(lowering.callableViews.requiredLocals.length, 7)
		assert.equal(lowering.callableViews.entries.length, 7)
		assert.equal(lowering.callableViews.entries.reduce((sum, entry) => sum + entry.unsafeOperations.length, 0), 8)
		assert.equal(lowering.callableViews.entries.reduce((sum, entry) => sum + entry.runtimeUses.length, 0), 2)
		if (!process.argv[3]) {
			// Focused contract tests run strict null-safety. Build this CLI once to
			// observe public behavior without recompiling it for every mutation.
			const built = await run(process.env.HAXE_BIN || path.join(root, 'node_modules/.bin/haxe'), [
				'-cp', 'packages/reflaxe.ocaml/src', '-D', 'reflaxe_runtime',
				'-main', 'reflaxe.ocaml.tooling.ReflaxeOcamlRun', '--neko', inspector
			])
			assert.equal(built.status, 0, built.stdout + built.stderr)
		}
		async function inspect(directory) {
			const result = await run('neko', [inspector, 'inspect', '--project', root, '--output', directory, '--require-lowering', '--json'])
			assert(result.stdout.length, result.stderr)
			return {status: result.status, report: JSON.parse(result.stdout)}
		}
		const good = await inspect(output)
		assert.equal(good.status, 0)
		assert.equal(good.report.schemaVersion, 52)
		assert.equal(good.report.summary.valid, true)
		assert.deepEqual(good.report.lowering.callableViews, lowering.callableViews)
		const cases = [
			['missing conversion', report => report.callableViews.entries.pop()],
			['missing required local', report => report.callableViews.requiredLocals.pop()],
			['stale body', report => { report.callableViews.entries[0].decision.binding.bodyRevision = 'foreign-body' }],
			['wrong adapter', report => { report.callableViews.entries.find(entry => entry.decision.adapter.conversion.kind === 'adapt-function').decision.adapter.conversion = {kind: 'identity', parameter: null, children: []} }],
			['missing unsafe evidence', report => report.callableViews.entries.find(entry => entry.unsafeOperations.length).unsafeOperations.pop()],
			['missing helper use', report => report.callableViews.entries.find(entry => entry.runtimeUses.length).runtimeUses.pop()],
			['missing helper requirement', report => {
				const id = report.callableViews.entries.find(entry => entry.runtimeUses.length).runtimeUses[0].requirementId
				report.runtimeRequirements = report.runtimeRequirements.filter(requirement => requirement.id !== id)
				report.runtimeRequirementCount = report.runtimeRequirements.length
			}],
			['unexpected origin field', report => { report.callableViews.entries[0].decision.input.unchecked = true }]
		]
		let next = 0
		// Copies share no mutable output. Two inspectors bound CPU use while avoiding
		// serial report hashing; each still gets a fresh process and its own result.
		async function worker() {
			while (next < cases.length) {
				const index = next++
				const [label, mutate] = cases[index]
				const destination = path.join(temporary, String(index))
				fs.cpSync(output, destination, {recursive: true, filter: file => path.basename(file) !== '_build'})
				const changed = structuredClone(lowering)
				mutate(changed)
				fs.writeFileSync(path.join(destination, 'ocaml_lowering_report.json'), JSON.stringify(changed))
				const result = await inspect(destination)
				assert.notEqual(result.status, 0, label)
				assert.equal(result.report.lowering.status, 'invalid', label)
				assert.match(result.report.lowering.message, /callback|Callback|report|Report/, label)
			}
		}
		const workers = await Promise.allSettled([worker(), worker()])
		const failed = workers.find(result => result.status === 'rejected')
		if (failed) throw failed.reason
		console.log('CALLBACK_PUBLIC_REPORT_AND_CORRUPTION:PASS')
	} finally {
		fs.rmSync(temporary, {recursive: true, force: true})
	}
}
main().catch(error => { console.error(error); process.exitCode = 1 })
