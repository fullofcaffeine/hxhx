#!/usr/bin/env node
/**
 * Inventory external GitHub Actions and reject deprecated embedded runtimes.
 *
 * A workflow action runs with the JavaScript runtime declared by that action,
 * independently from the Node.js version selected for repository commands.
 * Keep each reviewed action family here so a new or downgraded pin fails CI.
 */

const fs = require('fs')
const path = require('path')

const workflowDirectory = path.resolve(__dirname, '../../.github/workflows')
const reviewedActions = new Map([
	['actions/cache', {
		ref: 'v5',
		runtime: 'node24',
		replaces: 'v4 (node20)',
		minimumRunner: '2.327.1',
		source: 'https://github.com/actions/cache#whats-new'
	}],
	['actions/checkout', {
		ref: 'v5',
		runtime: 'node24',
		replaces: 'v4 (node20)',
		minimumRunner: '2.327.1',
		source: 'https://github.com/actions/checkout/releases/tag/v5.0.0'
	}],
	['actions/download-artifact', {
		ref: 'v7',
		runtime: 'node24',
		replaces: 'v4 (node20)',
		minimumRunner: '2.327.1',
		source: 'https://github.com/actions/download-artifact/releases/tag/v7.0.0'
	}],
	['actions/setup-node', {
		ref: 'v5',
		runtime: 'node24',
		replaces: 'v4 (node20)',
		minimumRunner: '2.327.1',
		source: 'https://github.com/actions/setup-node/releases/tag/v5.0.0'
	}],
	['actions/upload-artifact', {
		ref: 'v6',
		runtime: 'node24',
		replaces: 'v4 (node20)',
		minimumRunner: '2.327.1',
		source: 'https://github.com/actions/upload-artifact/releases/tag/v6.0.0'
	}],
	['github/codeql-action', {
		ref: 'v4',
		runtime: 'node24',
		replaces: 'v3 (node20)',
		minimumRunner: '2.327.1',
		source: 'https://github.com/github/codeql-action/blob/main/CHANGELOG.md'
	}],
	['ocaml/setup-ocaml', {
		ref: 'v3',
		runtime: 'node24',
		replaces: null,
		minimumRunner: '2.327.1',
		source: 'https://github.com/ocaml/setup-ocaml/blob/v3/action.yml'
	}]
])

function fail(message) {
	console.error(`[github-actions-runtime-check] ERROR: ${message}`)
	process.exitCode = 1
}

const observedActions = new Map()
const workflowFiles = fs.readdirSync(workflowDirectory)
	.filter((name) => /\.ya?ml$/.test(name))
	.sort()

for (const fileName of workflowFiles) {
	const filePath = path.join(workflowDirectory, fileName)
	const workflow = fs.readFileSync(filePath, 'utf8')
	if (/\bself-hosted\b/.test(workflow)) {
		fail(`${path.relative(process.cwd(), filePath)} needs a separate Node.js 24 runner review`)
	}
	const lines = workflow.split('\n')
	for (let index = 0; index < lines.length; index += 1) {
		const match = lines[index].match(/^\s*uses:\s*([^@\s#]+)@([^\s#]+)/)
		if (!match || match[1].startsWith('./')) continue

		const ownerAndAction = match[1].split('/').slice(0, 2).join('/')
		const location = `${path.relative(process.cwd(), filePath)}:${index + 1}`
		const reviewed = reviewedActions.get(ownerAndAction)
		if (!reviewed) {
			fail(`${location} uses unreviewed external action ${ownerAndAction}@${match[2]}`)
			continue
		}
		if (match[2] !== reviewed.ref) {
			fail(`${location} uses ${ownerAndAction}@${match[2]}; expected ${reviewed.ref}`)
		}
		if (ownerAndAction === 'actions/setup-node') {
			const setupInputs = lines.slice(index + 1, index + 8).join('\n')
			if (!/^\s+(cache|package-manager-cache):/m.test(setupInputs)) {
				fail(`${location} must state whether setup-node owns the package cache`)
			}
		}
		observedActions.set(ownerAndAction, (observedActions.get(ownerAndAction) ?? 0) + 1)
	}
}

for (const [ownerAndAction, reviewed] of reviewedActions) {
	if (!observedActions.has(ownerAndAction)) {
		fail(`reviewed action ${ownerAndAction}@${reviewed.ref} is absent from active workflows`)
	}
}

if (!process.exitCode) {
	console.log('[github-actions-runtime-check] Reviewed external action inventory:')
	for (const [ownerAndAction, reviewed] of reviewedActions) {
		const migration = reviewed.replaces ? `; replaces ${reviewed.replaces}` : ''
		console.log(
			`- ${ownerAndAction}@${reviewed.ref}: ${reviewed.runtime}; ${observedActions.get(ownerAndAction)} uses; runner >= ${reviewed.minimumRunner}${migration}; ${reviewed.source}`
		)
	}
	console.log('GITHUB_ACTIONS_NODE24_RUNTIME_INVENTORY:PASS')
}
