#!/usr/bin/env node

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const repositoryRoot = path.resolve(__dirname, '../..')
const fixtureRoots = []

function assert(condition, message) {
	if (!condition) throw new Error(message)
}

function run(command, args, options = {}) {
	const result = spawnSync(command, args, {
		cwd: options.cwd,
		env: options.env || process.env,
		encoding: 'utf8',
	})

	if (options.expectFailure) {
		assert(result.status !== 0, `${command} ${args.join(' ')} should fail`)
		return result
	}

	if (result.status !== 0) {
		throw new Error(
			`${command} ${args.join(' ')} failed (${result.status})\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
		)
	}

	return result
}

function writeExecutable(filePath, contents) {
	fs.writeFileSync(filePath, contents)
	fs.chmodSync(filePath, 0o755)
}

function makeFixture(name, initialPostCheckout) {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), `hxhx-post-checkout-${name}-`))
	fixtureRoots.push(root)

	const scriptsDir = path.join(root, 'scripts')
	const hooksSourceDir = path.join(scriptsDir, 'hooks')
	const fakeBinDir = path.join(root, 'fake-bin')
	fs.mkdirSync(hooksSourceDir, { recursive: true })
	fs.mkdirSync(fakeBinDir, { recursive: true })

	fs.copyFileSync(path.join(repositoryRoot, 'scripts/install-git-hooks.sh'), path.join(scriptsDir, 'install-git-hooks.sh'))
	fs.copyFileSync(path.join(repositoryRoot, 'scripts/hooks/pre-commit'), path.join(hooksSourceDir, 'pre-commit'))
	fs.copyFileSync(path.join(repositoryRoot, 'scripts/hooks/post-checkout'), path.join(hooksSourceDir, 'post-checkout'))
	fs.copyFileSync(path.join(repositoryRoot, 'scripts/hooks/post-commit'), path.join(hooksSourceDir, 'post-commit'))

	run('git', ['init', '-q'], { cwd: root })
	run('git', ['config', 'user.name', 'Hook Fixture'], { cwd: root })
	run('git', ['config', 'user.email', 'hook-fixture@example.invalid'], { cwd: root })
	run('git', ['commit', '-q', '--allow-empty', '-m', 'hook fixture'], { cwd: root })
	const head = run('git', ['rev-parse', 'HEAD'], { cwd: root }).stdout.trim()
	const hooksDir = path.join(root, '.git', 'hooks')
	if (initialPostCheckout != null) {
		writeExecutable(path.join(hooksDir, 'post-checkout'), initialPostCheckout)
	}

	const bdLog = path.join(root, 'bd.log')
	const userLog = path.join(root, 'user.log')
	writeExecutable(
		path.join(fakeBinDir, 'bd'),
		'#!/usr/bin/env bash\nset -euo pipefail\nprintf "%s\\n" "$*" >> "${HXHX_HOOK_FIXTURE_BD_LOG:?}"\nif [[ "${HXHX_HOOK_FIXTURE_BD_FAIL:-0}" == "1" ]]; then exit 9; fi\n',
	)

	const env = {
		...process.env,
		PATH: `${fakeBinDir}${path.delimiter}${process.env.PATH || ''}`,
		HXHX_HOOKS_INSTALL_ROOT: root,
		HXHX_HOOK_FIXTURE_BD_LOG: bdLog,
		HXHX_HOOK_FIXTURE_USER_LOG: userLog,
	}

	return { root, hooksDir, bdLog, userLog, env, head }
}

function install(fixture, expectFailure = false) {
	return run('bash', ['scripts/install-git-hooks.sh'], {
		cwd: fixture.root,
		env: fixture.env,
		expectFailure,
	})
}

function invoke(fixture, args, options = {}) {
	for (const logPath of [fixture.bdLog, fixture.userLog]) {
		fs.rmSync(logPath, { force: true })
	}

	return run(path.join(fixture.hooksDir, 'post-checkout'), args, {
		cwd: fixture.root,
		env: {
			...fixture.env,
			...(options.env || {}),
			HXHX_HOOK_TRACE: options.trace ? '1' : '0',
		},
		expectFailure: options.expectFailure,
	})
}

function logLines(logPath) {
	if (!fs.existsSync(logPath)) return []
	return fs
		.readFileSync(logPath, 'utf8')
		.trim()
		.split('\n')
		.filter(Boolean)
}

function testOfficialBeadsShim() {
	const officialShim =
		'#!/usr/bin/env sh\n# bd-shim v1\nif ! command -v bd >/dev/null 2>&1; then exit 0; fi\nexec bd hooks run post-checkout "$@"\n'
	const fixture = makeFixture('bd-shim', officialShim)
	install(fixture)

	const primary = path.join(fixture.hooksDir, 'post-checkout')
	const delegate = path.join(fixture.hooksDir, 'post-checkout.bd')
	const postCommit = path.join(fixture.hooksDir, 'post-commit')
	const checkoutState = path.join(fixture.root, '.git', 'hxhx-post-checkout-state')
	assert(fs.readFileSync(delegate, 'utf8') === officialShim, 'the exact Beads shim must be preserved')
	assert(
		fs.readFileSync(primary, 'utf8').includes('HXHX_BD_POST_CHECKOUT_FAST_PATH_V1'),
		'the repository fast guard must become the primary hook',
	)
	assert((fs.statSync(primary).mode & 0o111) !== 0, 'the primary hook must remain executable')
	assert(
		fs.readFileSync(postCommit, 'utf8').includes('HXHX_BD_POST_COMMIT_STATE_V1'),
		'the repository post-commit state hook must be installed',
	)
	const installedState = fs.readFileSync(checkoutState, 'utf8')
	assert(installedState.startsWith('branch:'), 'the installer must record the current branch identity')
	assert(installedState.includes(fixture.head), 'the checkout state must include the synchronized HEAD commit')

	run('git', ['commit', '-q', '--no-verify', '--allow-empty', '-m', 'local commit advances checkout state'], {
		cwd: fixture.root,
		env: fixture.env,
	})
	const shaA = run('git', ['rev-parse', 'HEAD'], { cwd: fixture.root }).stdout.trim()
	assert(shaA !== fixture.head, 'the local commit control must advance HEAD')
	assert(fs.readFileSync(checkoutState, 'utf8').includes(shaA), 'post-commit must advance the synchronized HEAD state')
	const shaB = 'b'.repeat(40)
	const same = invoke(fixture, [shaA, shaA, '1'], { trace: true })
	assert(same.stdout.includes('skipped redundant Beads import'), 'the traced identical-commit path must say what it skipped')
	assert(logLines(fixture.bdLog).length === 0, 'an identical branch checkout must not invoke Beads')

	const branchRef = run('git', ['symbolic-ref', 'HEAD'], { cwd: fixture.root }).stdout.trim()
	const branchName = branchRef.replace(/^refs\/heads\//, '')
	const emptyHooks = path.join(fixture.root, 'empty-hooks')
	fs.mkdirSync(emptyHooks)
	run('git', ['-c', `core.hooksPath=${emptyHooks}`, 'switch', '-q', '--detach', shaA], { cwd: fixture.root })
	const rebaseStateDir = path.join(fixture.root, '.git', 'rebase-merge')
	fs.mkdirSync(rebaseStateDir)
	fs.writeFileSync(path.join(rebaseStateDir, 'head-name'), `${branchRef}\n`)
	invoke(fixture, [shaA, shaA, '1'])
	assert(logLines(fixture.bdLog).length === 0, 'a no-op rebase must retain its recorded branch while HEAD is detached')
	fs.rmSync(rebaseStateDir, { recursive: true, force: true })
	run('git', ['-c', `core.hooksPath=${emptyHooks}`, 'switch', '-q', branchName], { cwd: fixture.root })

	fs.writeFileSync(checkoutState, 'branch:refs/heads/different\n')
	invoke(fixture, [shaA, shaA, '1'], {
		expectFailure: true,
		env: { HXHX_HOOK_FIXTURE_BD_FAIL: '1' },
	})
	assert(
		fs.readFileSync(checkoutState, 'utf8') === 'branch:refs/heads/different\n',
		'a failed Beads delegate must not mark the checkout as synchronized',
	)
	invoke(fixture, [shaA, shaA, '1'])
	assert(logLines(fixture.bdLog).length === 1, 'an equal-commit switch from a different branch must delegate to Beads')
	invoke(fixture, [shaA, shaA, '1'])
	assert(logLines(fixture.bdLog).length === 0, 'a successful delegate must record the current branch for the next no-op')

	invoke(fixture, [shaA, shaB, '1'])
	assert(
		logLines(fixture.bdLog)[0] === `hooks run post-checkout ${shaA} ${shaB} 1`,
		'a changed branch checkout must delegate exact arguments to Beads',
	)

	invoke(fixture, [shaA, shaA, '0'])
	assert(logLines(fixture.bdLog).length === 1, 'a file checkout must still delegate to Beads')

	invoke(fixture, ['not-a-sha', 'not-a-sha', '1'])
	assert(logLines(fixture.bdLog).length === 1, 'malformed equal values must not enter the fast path')

	invoke(fixture, [])
	assert(logLines(fixture.bdLog).length === 1, 'missing arguments must retain canonical Beads handling')

	invoke(fixture, ['c'.repeat(64), 'c'.repeat(64), '1'])
	assert(logLines(fixture.bdLog).length === 1, 'a valid object ID that is not the current HEAD must delegate')

	install(fixture)
	assert(fs.readFileSync(delegate, 'utf8') === officialShim, 'reinstall must not replace the Beads delegate')
}

function testUserHookChaining() {
	const userHook =
		'#!/usr/bin/env bash\nset -euo pipefail\nprintf "user:%s\\n" "$*" >> "${HXHX_HOOK_FIXTURE_USER_LOG:?}"\n'
	const fixture = makeFixture('user-hook', userHook)
	const userPostCommit =
		'#!/usr/bin/env bash\nset -euo pipefail\nprintf "commit-user\\n" >> "${HXHX_HOOK_FIXTURE_USER_LOG:?}"\n'
	writeExecutable(path.join(fixture.hooksDir, 'post-commit'), userPostCommit)
	install(fixture)

	const preservedUserHook = path.join(fixture.hooksDir, 'post-checkout.user')
	const preservedUserPostCommit = path.join(fixture.hooksDir, 'post-commit.user')
	assert(fs.readFileSync(preservedUserHook, 'utf8') === userHook, 'an existing user hook must be preserved exactly')
	assert(
		fs.readFileSync(preservedUserPostCommit, 'utf8') === userPostCommit,
		'an existing user post-commit hook must be preserved exactly',
	)

	fs.rmSync(fixture.userLog, { force: true })
	run('git', ['commit', '-q', '--no-verify', '--allow-empty', '-m', 'user post-commit control'], {
		cwd: fixture.root,
		env: fixture.env,
	})
	assert(logLines(fixture.userLog)[0] === 'commit-user', 'the preserved user post-commit hook must still run')
	const shaA = run('git', ['rev-parse', 'HEAD'], { cwd: fixture.root }).stdout.trim()
	const shaB = 'e'.repeat(40)
	invoke(fixture, [shaA, shaA, '1'])
	assert(logLines(fixture.userLog)[0] === `user:${shaA} ${shaA} 1`, 'the user hook must observe identical checkouts')
	assert(logLines(fixture.bdLog).length === 0, 'the Beads import must still be skipped after the user hook')

	invoke(fixture, [shaA, shaB, '1'])
	assert(logLines(fixture.userLog).length === 1, 'the user hook must observe changed checkouts')
	assert(logLines(fixture.bdLog).length === 1, 'changed checkouts must fall back to the current Beads CLI')

	install(fixture)
	assert(fs.readFileSync(preservedUserHook, 'utf8') === userHook, 'idempotent reinstall must retain the user hook')
	assert(
		fs.readFileSync(preservedUserPostCommit, 'utf8') === userPostCommit,
		'idempotent reinstall must retain the user post-commit hook',
	)
}

function testConflictingUserHookFailsClosed() {
	const fixture = makeFixture('user-conflict', '#!/usr/bin/env bash\nexit 0\n')
	fs.writeFileSync(path.join(fixture.hooksDir, 'post-checkout.user'), '#!/usr/bin/env bash\nexit 7\n')
	const result = install(fixture, true)
	assert(result.stderr.includes('refusing to replace existing post-checkout.user'), 'a conflicting user hook must fail closed')
}

function testRealBeadsCheckout() {
	const sourceRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-post-checkout-real-source-'))
	const cloneParent = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-post-checkout-real-clone-'))
	const targetRoot = path.join(cloneParent, 'target')
	fixtureRoots.push(sourceRoot, cloneParent)

	run('git', ['init', '-q'], { cwd: sourceRoot })
	run('git', ['config', 'user.name', 'Hook Fixture'], { cwd: sourceRoot })
	run('git', ['config', 'user.email', 'hook-fixture@example.invalid'], { cwd: sourceRoot })
	run('bd', ['init', '--non-interactive', '--skip-hooks', '--skip-agents', '--prefix', 'hooktest'], { cwd: sourceRoot })
	run(
		'bd',
		[
			'create',
			'Base issue',
			'--description',
			'Base state for the real post-checkout import fixture.',
			'--type',
			'task',
			'--priority',
			'2',
			'--silent',
		],
		{ cwd: sourceRoot },
	)
	run('bd', ['export', '-o', '.beads/issues.jsonl'], { cwd: sourceRoot })
	run('git', ['add', '-f', '.beads/issues.jsonl'], { cwd: sourceRoot })
	run('git', ['commit', '-q', '-m', 'base tracker state'], { cwd: sourceRoot })
	const sourceBranch = run('git', ['branch', '--show-current'], { cwd: sourceRoot }).stdout.trim()
	assert(sourceBranch.length > 0, 'the source fixture must have a current branch')

	run('git', ['clone', '-q', sourceRoot, targetRoot], { cwd: cloneParent })
	run('git', ['config', 'user.name', 'Hook Fixture'], { cwd: targetRoot })
	run('git', ['config', 'user.email', 'hook-fixture@example.invalid'], { cwd: targetRoot })
	run('bd', ['init', '--from-jsonl', '--non-interactive', '--skip-hooks', '--skip-agents', '--prefix', 'hooktest'], {
		cwd: targetRoot,
	})
	const targetIssue = run(
		'bd',
		[
			'create',
			'Target issue',
			'--description',
			'This issue must enter the first repository through a changed checkout.',
			'--type',
			'task',
			'--priority',
			'2',
			'--silent',
		],
		{ cwd: targetRoot },
	).stdout.trim()
	assert(targetIssue.startsWith('hooktest-'), 'the target fixture issue must be created')
	run('bd', ['export', '-o', '.beads/issues.jsonl'], { cwd: targetRoot })
	run('git', ['add', '-f', '.beads/issues.jsonl'], { cwd: targetRoot })
	run('git', ['commit', '-q', '-m', 'target tracker state'], { cwd: targetRoot })

	run('git', ['remote', 'add', 'target-fixture', targetRoot], { cwd: sourceRoot })
	const targetRef = `refs/remotes/target-fixture/${sourceBranch}`
	run('git', ['fetch', '-q', 'target-fixture', `${sourceBranch}:${targetRef}`], { cwd: sourceRoot })
	const sourceHooksDir = path.join(sourceRoot, '.git', 'hooks')
	writeExecutable(
		path.join(sourceHooksDir, 'post-checkout'),
		fs.readFileSync(path.join(repositoryRoot, 'scripts/hooks/post-checkout'), 'utf8'),
	)
	run('git', ['switch', '-q', '-c', 'imported-tracker-state', targetRef], { cwd: sourceRoot })
	const imported = run('bd', ['--json', 'show', targetIssue], { cwd: sourceRoot })
	const importedIssues = JSON.parse(imported.stdout)
	assert(Array.isArray(importedIssues) && importedIssues.length === 1, 'the real Beads lookup must return one issue')
	const importedIssue = importedIssues[0]
	assert(importedIssue.id === targetIssue, 'a changed checkout must import the target branch issue into Beads')
}

try {
	testOfficialBeadsShim()
	testUserHookChaining()
	testConflictingUserHookFailsClosed()
	if (process.env.HXHX_REAL_BD_HOOK_SMOKE === '1') {
		testRealBeadsCheckout()
		console.log('[post-checkout-hook-fixture-test] real Beads checkout ok')
	}
	console.log('[post-checkout-hook-fixture-test] ok')
} finally {
	for (const root of fixtureRoots) fs.rmSync(root, { recursive: true, force: true })
}
