#!/usr/bin/env node

const cp = require('child_process')

function fail(msg) {
	console.error(`[ci:guards] ERROR: ${msg}`)
	process.exitCode = 1
}

function gitTrackedAll() {
	try {
		const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
		return out.split('\0').filter(Boolean)
	} catch (_) {
		return []
	}
}

function gitTrackedUnder(path) {
	try {
		const out = cp.execFileSync('git', ['ls-files', '-z', '--', path], { encoding: 'utf8' })
		return out.split('\0').filter(Boolean)
	} catch (_) {
		return []
	}
}

function summarize(paths, limit) {
	const slice = paths.slice(0, limit).map((path) => `- ${path}`)
	const suffix = paths.length > limit ? `\n- ... (${paths.length - limit} more)` : ''
	return `${slice.join('\n')}${suffix}`
}

const approvedUpstreamVendorRoots = ['vendor/haxe/std/']
const forbiddenUpstreamVendorRoots = [
	'vendor/haxe/src/',
	'vendor/haxe/tests/',
	'vendor/haxe/extra/',
	'vendor/haxe/.git/',
]
const approvedStdlibSyncTargets = ['packages/reflaxe.ocaml/std/_std/']

const tracked = gitTrackedAll()
const trackedVendor = gitTrackedUnder('vendor/haxe')
const trackedForbiddenVendor = trackedVendor.filter((path) =>
	forbiddenUpstreamVendorRoots.some((prefix) => path.startsWith(prefix))
)

if (trackedForbiddenVendor.length > 0) {
	fail(
		`forbidden upstream compiler/test paths are tracked under vendor/haxe:\n${summarize(trackedForbiddenVendor, 20)}`
	)
}

const trackedOutsideApprovedVendorRoots = trackedVendor.filter((path) =>
	!approvedUpstreamVendorRoots.some((prefix) => path.startsWith(prefix))
)

if (trackedOutsideApprovedVendorRoots.length > 0) {
	fail(
		`only upstream stdlib paths are ever eligible for vendoring (${approvedUpstreamVendorRoots.join(
			', '
		)}); found:\n${summarize(trackedOutsideApprovedVendorRoots, 20)}`
	)
}

if (trackedVendor.length > 0) {
	fail(
		`tracked files under vendor/haxe are not allowed in this repo. Keep vendor/haxe untracked and sync needed stdlib files into ${approvedStdlibSyncTargets.join(
			', '
		)}. Found:\n${summarize(trackedVendor, 20)}`
	)
}

const trackedStdlibTargets = tracked.filter((path) =>
	approvedStdlibSyncTargets.some((prefix) => path.startsWith(prefix))
)

for (const path of trackedStdlibTargets) {
	if (!path.endsWith('.hx')) {
		fail(
			`stdlib sync target contains a non-Haxe file: ${path}. Only checked-in .hx stdlib overrides are allowed in ${approvedStdlibSyncTargets.join(
				', '
			)}.`
		)
	}
}

if (process.exitCode) process.exit(process.exitCode)
console.log(
	`[ci:guards] OK: upstream stdlib boundary (vendor/haxe untracked; approved sync targets: ${approvedStdlibSyncTargets.join(
		', '
	)})`
)
