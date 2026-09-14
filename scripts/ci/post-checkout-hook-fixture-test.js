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
		timeout: 60000,
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

const officialShim = '#!/usr/bin/env sh\n# bd-shim v1\nexec bd hooks run post-checkout "$@"\n'

/** Exercise real Git notifications while treating any tracker invocation as a failure. */
function testNoAutomaticTrackerAccess() {
	for (const initial of [null, officialShim, '#!/usr/bin/env bash\n# HXHX_BD_POST_CHECKOUT_FAST_PATH_V1\nexit 0\n']) {
		const fixture = makeFixture('no-tracker', initial)
		writeExecutable(path.join(fixture.hooksDir, 'post-checkout.bd'), officialShim)
		writeExecutable(path.join(fixture.hooksDir, 'post-commit'), '#!/usr/bin/env bash\n# HXHX_BD_POST_COMMIT_STATE_V1\nexit 0\n')
		install(fixture)
		assert(!fs.existsSync(path.join(fixture.hooksDir, 'post-checkout.bd')), 'obsolete delegate must be retired')
		assert(fs.readFileSync(path.join(fixture.hooksDir, 'post-checkout.bd.retired'), 'utf8') === officialShim, 'retirement must preserve exact shim bytes')
		assert(!fs.existsSync(path.join(fixture.root, '.git', 'hxhx-post-checkout-state')), 'installation must not create synchronization state')
		const env = { ...fixture.env, HXHX_HOOK_FIXTURE_BD_FAIL: '1' }
		run('git', ['switch', '-q', '-c', 'new-task'], { cwd: fixture.root, env })
		run('git', ['commit', '-q', '--no-verify', '--allow-empty', '-m', 'advance'], { cwd: fixture.root, env })
		run('git', ['switch', '-q', '--detach', fixture.head], { cwd: fixture.root, env })
		assert(logLines(fixture.bdLog).length === 0, 'branch creation, commit, and changed checkout must never invoke Beads')
		for (const args of [[fixture.head, fixture.head, '1'], [fixture.head, fixture.head, '0'], []]) {
			invoke(fixture, args, { env })
			assert(logLines(fixture.bdLog).length === 0, 'no checkout argument shape may invoke Beads')
		}
		install(fixture)
		assert(fs.readFileSync(path.join(fixture.hooksDir, 'post-checkout.bd.retired'), 'utf8') === officialShim, 'reinstall must preserve the retired shim')
	}
}

function testUserHookChaining() {
	const userHook = '#!/usr/bin/env bash\nprintf "user:%s\\n" "$*" >> "${HXHX_HOOK_FIXTURE_USER_LOG:?}"\n'
	const userPostCommit = '#!/usr/bin/env bash\nprintf "commit-user\\n" >> "${HXHX_HOOK_FIXTURE_USER_LOG:?}"\n'
	const fixture = makeFixture('user-hook', userHook)
	writeExecutable(path.join(fixture.hooksDir, 'post-commit'), userPostCommit)
	install(fixture)
	install(fixture)
	assert(fs.readFileSync(path.join(fixture.hooksDir, 'post-checkout.user'), 'utf8') === userHook, 'preserve user checkout hook exactly')
	assert(fs.readFileSync(path.join(fixture.hooksDir, 'post-commit.user'), 'utf8') === userPostCommit, 'preserve user commit hook exactly')
	for (const args of [[fixture.head, fixture.head, '1'], [fixture.head, 'e'.repeat(40), '1'], [fixture.head, fixture.head, '0']]) {
		invoke(fixture, args)
		assert(logLines(fixture.userLog)[0] === `user:${args.join(' ')}`, 'preserve exact user-hook arguments')
		assert(logLines(fixture.bdLog).length === 0, 'user-hook chaining must not add a Beads call')
	}
	fs.rmSync(fixture.userLog, { force: true })
	run('git', ['commit', '-q', '--no-verify', '--allow-empty', '-m', 'user commit'], { cwd: fixture.root, env: fixture.env })
	assert(logLines(fixture.userLog).join('') === 'commit-user', 'user post-commit hook must run once')
	writeExecutable(path.join(fixture.hooksDir, 'post-checkout.user'), '#!/usr/bin/env bash\nexit 7\n')
	const failed = invoke(fixture, [fixture.head, fixture.head, '1'], { expectFailure: true })
	assert(failed.status === 7, 'user hook failure must remain visible')
}

function testConflictingUserHookFailsClosed() {
	const fixture = makeFixture('user-conflict', '#!/usr/bin/env bash\nexit 0\n')
	fs.writeFileSync(path.join(fixture.hooksDir, 'post-checkout.user'), '#!/usr/bin/env bash\nexit 7\n')
	const result = install(fixture, true)
	assert(result.stderr.includes('refusing to replace existing post-checkout.user'), 'conflicting user hooks must fail closed')
	const retired = makeFixture('archive-conflict', officialShim)
	const archive = path.join(retired.hooksDir, 'post-checkout.bd.retired')
	fs.writeFileSync(archive, 'previous archived hook')
	assert(install(retired, true).stderr.includes('refusing to replace a different retired Beads hook'), 'conflicting archives must fail closed')
	assert(fs.readFileSync(archive, 'utf8') === 'previous archived hook', 'failed retirement must preserve the existing archive')
	assert(fs.readFileSync(path.join(retired.hooksDir, 'post-checkout'), 'utf8') === officialShim, 'failed retirement must preserve the source shim')
}

/** A pinned real database must survive stale exports, including an ID already stored as a wisp. */
function testRealBeadsCheckout() {
	const bd = process.env.HXHX_REVIEWED_BD_BIN
	const toolchain = process.env.HXHX_REVIEWED_BD_TOOLCHAIN
	assert(bd && path.isAbsolute(bd) && toolchain && path.isAbsolute(toolchain), 'real smoke requires absolute reviewed Beads wrapper and toolchain paths')
	const fixture = makeFixture('real-database', officialShim)
	// Do not let an outer Beads session select a database outside this fixture.
	const cleanEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/^(BEADS_|BD_)/.test(key)))
	const env = { ...cleanEnv, HXHX_HOOKS_INSTALL_ROOT: fixture.root }
	fs.copyFileSync(path.join(repositoryRoot, '.beads-toolchain'), path.join(fixture.root, '.beads-toolchain'))
	run(toolchain, ['check', '--repository', fixture.root], { cwd: fixture.root, env })
	run(bd, ['init', '--non-interactive', '--skip-hooks', '--skip-agents', '--prefix', 'hooktest'], { cwd: fixture.root, env })
	run(bd, ['--readonly', 'info', '--json'], { cwd: fixture.root, env })
	run('git', ['add', '-f', '.beads-toolchain', '.beads/config.yaml', '.beads/metadata.json'], { cwd: fixture.root, env })
	run('git', ['-c', 'core.hooksPath=/dev/null', 'commit', '-q', '-m', 'tracker configuration'], { cwd: fixture.root, env })
	const configuredHead = run('git', ['rev-parse', 'HEAD'], { cwd: fixture.root, env }).stdout.trim()
	const bead = (args) => run(bd, ['--actor', 'hook-fixture', ...args], { cwd: fixture.root, env })
	bead(['create', 'Newer live issue', '--id', 'hooktest-live', '--description', 'Authoritative current value', '--type', 'task'])
	bead(['create', 'Live ephemeral issue', '--id', 'hooktest-collision', '--description', 'Must not be imported as a versioned issue', '--ephemeral', '--type', 'task'])
	const live = JSON.parse(bead(['--readonly', 'show', 'hooktest-live', '--json']).stdout)
	const wisp = JSON.parse(bead(['--readonly', 'show', 'hooktest-collision', '--json']).stdout)
	const stale = { ...live[0], title: 'Older exported title', status: 'closed' }
	const collision = { ...wisp[0], ephemeral: false, storage_class: 'versioned' }
	const exportPath = path.join(fixture.root, '.beads', 'issues.jsonl')
	fs.writeFileSync(exportPath, `${JSON.stringify(stale)}\n${JSON.stringify(collision)}\n`)
	run('git', ['add', '-f', '.beads/issues.jsonl'], { cwd: fixture.root, env })
	run('git', ['-c', 'core.hooksPath=/dev/null', 'commit', '-q', '-m', 'stale branch export'], { cwd: fixture.root, env })
	install(fixture)
	const before = bead(['export']).stdout
	run('git', ['switch', '-q', '-c', 'new-branch-same-sha'], { cwd: fixture.root, env })
	assert(bead(['export']).stdout === before, 'same-SHA branch creation must preserve every live exported field')
	assert(JSON.stringify(JSON.parse(bead(['--readonly', 'show', 'hooktest-collision', '--json']).stdout)) === JSON.stringify(wisp), 'colliding live wisp must remain unchanged')
	run('git', ['worktree', 'add', '-q', '-b', 'linked-task', path.join(fixture.root, 'linked'), 'HEAD'], { cwd: fixture.root, env })
	assert(bead(['export']).stdout === before, 'linked-worktree creation must preserve the shared live database')
	run('git', ['switch', '-q', '--detach', configuredHead], { cwd: fixture.root, env })
	assert(bead(['export']).stdout === before, 'changed-SHA checkout must preserve live task contents too')
}

try {
	testNoAutomaticTrackerAccess()
	testUserHookChaining()
	testConflictingUserHookFailsClosed()
	if (process.env.HXHX_REAL_BD_HOOK_SMOKE === '1') {
		testRealBeadsCheckout()
		console.log('[post-checkout-hook-fixture-test] real Beads authority preserved')
	}
	console.log('[post-checkout-hook-fixture-test] ok')
} finally {
	for (const root of fixtureRoots) fs.rmSync(root, { recursive: true, force: true })
}
