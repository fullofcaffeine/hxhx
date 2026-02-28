#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

function fail(message) {
	console.error(`[stdlib-closure-sync] ERROR: ${message}`)
	process.exit(1)
}

function runCommand(command, args) {
	const output = cp.execFileSync(command, args, {
		cwd: process.cwd(),
		encoding: 'utf8',
		stdio: ['ignore', 'pipe', 'pipe'],
	})
	return output
}

function loadOpenIssues() {
	const output = runCommand('bd', ['list', '--json'])
	const parsed = JSON.parse(output)
	if (!Array.isArray(parsed)) {
		fail('bd list --json did not return an issue array')
	}
	return parsed
}

function buildDescription(bucket) {
	const modulesList = bucket.modules.map((moduleName) => `- \`${moduleName}\``).join('\n')
	return [
		`Close portable parity gaps for closure bucket \`${bucket.bucketKey}\` (group: \`${bucket.group}\`).`,
		'',
		'Modules in scope:',
		modulesList,
		'',
		'Requirements:',
		'- Add fixture evidence for each module behavior closed in this bucket',
		'- Link docs/matrix evidence updates in the same change',
		'- Keep portable lane strict (`ocaml_portable_native_surface=error`) green',
	].join('\n')
}

function main() {
	const applyChanges = process.argv.includes('--apply')
	const repoRoot = path.resolve(__dirname, '..', '..')
	const worklistPath = path.join(repoRoot, 'docs', '00-project', 'STDLIB_PORTABLE_CLOSURE_WORKLIST_HAXE_4_3_7.json')
	const parentIssueId = 'haxe.ocaml-yfh.5'

	if (!fs.existsSync(worklistPath)) {
		fail(`missing worklist file: ${worklistPath}. Run generate-portable-closure-worklist.js first.`)
	}

	const worklist = JSON.parse(fs.readFileSync(worklistPath, 'utf8'))
	if (!Array.isArray(worklist.buckets)) {
		fail(`worklist file has no buckets array: ${worklistPath}`)
	}

	const existingIssues = loadOpenIssues()
	const existingByExternalRef = new Map()
	for (const issue of existingIssues) {
		if (typeof issue.external_ref === 'string' && issue.external_ref.startsWith('m16-closure:')) {
			existingByExternalRef.set(issue.external_ref, issue)
		}
	}

	let createdCount = 0
	let updatedCount = 0
	let existingCount = 0
	const expectedRefs = new Set()

	for (const bucket of worklist.buckets) {
		const externalRef = `m16-closure:${bucket.bucketKey}`
		expectedRefs.add(externalRef)
		const title = `M16.5 closure bucket ${bucket.bucketKey} (${bucket.modules.length} modules)`
		const description = buildDescription(bucket)
		const acceptance = [
			'- All modules in this bucket have fixture evidence and doc linkage',
			'- Parity matrix entries for these modules are no longer unverified',
			'- Portable strict lane remains green in CI',
		].join('\\n')
		const existing = existingByExternalRef.get(externalRef)
		if (existing != null) {
			existingCount += 1
			const needsUpdate =
				existing.title !== title ||
				existing.description !== description ||
				existing.acceptance_criteria !== acceptance
			if (needsUpdate) {
				if (applyChanges) {
					runCommand('bd', [
						'update',
						existing.id,
						'--title',
						title,
						'--description',
						description,
						'--acceptance',
						acceptance,
					])
					updatedCount += 1
					console.log(`[stdlib-closure-sync] updated ${existing.id} (${externalRef})`)
				} else {
					console.log(`[stdlib-closure-sync] would update ${existing.id} (${externalRef})`)
				}
			} else {
				console.log(`[stdlib-closure-sync] keep ${existing.id} (${externalRef})`)
			}
			continue
		}

		const args = [
			'create',
			title,
			'--type',
			'task',
			'--priority',
			'1',
			'--labels',
			'area:stdlib,phase:1.0,m16:closure-bucket',
			'--parent',
			parentIssueId,
			'--external-ref',
			externalRef,
			'--description',
			description,
			'--acceptance',
			acceptance,
		]
		if (!applyChanges) {
			args.push('--dry-run')
		}

		const output = runCommand('bd', args)
		console.log(output.trim())
		if (applyChanges) {
			createdCount += 1
		}
	}

	const stale = []
	for (const [externalRef, issue] of existingByExternalRef.entries()) {
		if (!expectedRefs.has(externalRef)) {
			stale.push(issue)
		}
	}

	if (stale.length > 0) {
		console.log('[stdlib-closure-sync] stale closure tasks detected (not auto-closed):')
		for (const issue of stale) {
			console.log(`- ${issue.id} (${issue.external_ref})`)
		}
	}

	console.log(
		`[stdlib-closure-sync] summary: ${worklist.buckets.length} buckets, ${existingCount} existing, ${updatedCount} updated, ${createdCount} created${
			applyChanges ? '' : ' (dry-run)'
		}`
	)
}

main()
