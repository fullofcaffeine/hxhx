#!/usr/bin/env node
/** Prepares tracked source inputs for a deterministic reflaxe.ocaml haxelib ZIP. */
const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const defaultEpochSeconds = 315532800 // 1980-01-01T00:00:00Z, the earliest portable ZIP timestamp.
const forbiddenBinaryExtensions = new Set([
	'.a',
	'.cma',
	'.cmi',
	'.cmo',
	'.cmx',
	'.cmxa',
	'.cmxs',
	'.dll',
	'.dylib',
	'.exe',
	'.n',
	'.ndll',
	'.o',
	'.obj',
	'.so'
])

function fail(message) {
	console.error(`[prepare-haxelib-archive] ERROR: ${message}`)
	process.exit(1)
}

function parseArgs(argv) {
	const [command, ...rest] = argv
	const values = {}
	for (let index = 0; index < rest.length; index += 2) {
		const key = rest[index]
		const value = rest[index + 1]
		if (!key || !key.startsWith('--') || value == null) {
			fail(`invalid arguments: ${rest.join(' ')}`)
		}
		values[key.slice(2)] = value
	}
	return { command, values }
}

function requireValue(values, name) {
	const value = values[name]
	if (!value) {
		fail(`missing required --${name} argument`)
	}
	return value
}

function isInside(parent, child) {
	const relative = path.relative(parent, child)
	return relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)
}

/**
 * Copies only Git-tracked package inputs from the current working tree.
 *
 * Reading the working tree keeps intentional uncommitted edits testable, while
 * the Git manifest prevents ignored compiler outputs from leaking into a release.
 */
function stageTrackedPackage(values) {
	const packageRelative = requireValue(values, 'package')
	const outputRoot = path.resolve(requireValue(values, 'out'))
	const sourceRepo = path.resolve(values.repo || repoRoot)
	const packageRoot = path.resolve(sourceRepo, packageRelative)
	if (!isInside(sourceRepo, packageRoot)) {
		fail(`package path must be inside the repository: ${packageRelative}`)
	}

	const listed = cp.spawnSync('git', ['ls-files', '-z', '--', packageRelative], {
		cwd: sourceRepo,
		encoding: 'buffer',
		shell: false
	})
	if (listed.status !== 0) {
		fail(`git ls-files failed: ${String(listed.stderr || '').trim()}`)
	}

	const files = listed.stdout
		.toString('utf8')
		.split('\0')
		.filter(Boolean)
		.sort()
	if (files.length === 0) {
		fail(`no tracked files found under ${packageRelative}`)
	}

	fs.rmSync(outputRoot, { recursive: true, force: true })
	fs.mkdirSync(outputRoot, { recursive: true })
	for (const trackedRelative of files) {
		const source = path.resolve(sourceRepo, trackedRelative)
		if (!isInside(packageRoot, source)) {
			fail(`tracked path escaped package root: ${trackedRelative}`)
		}
		const packagePath = path.relative(packageRoot, source)
		if (packagePath.includes('\n') || packagePath.includes('\r')) {
			fail(`package paths containing newlines are unsupported: ${JSON.stringify(packagePath)}`)
		}
		const stat = fs.lstatSync(source)
		if (!stat.isFile()) {
			fail(`package input must be a regular file: ${trackedRelative}`)
		}
		const destination = path.join(outputRoot, packagePath)
		fs.mkdirSync(path.dirname(destination), { recursive: true })
		fs.copyFileSync(source, destination)
	}

	console.log(`[prepare-haxelib-archive] staged ${files.length} tracked files`)
}

function visitFiles(root, current, files) {
	for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
		const absolute = path.join(current, entry.name)
		if (entry.isDirectory()) {
			visitFiles(root, absolute, files)
			continue
		}
		if (!entry.isFile()) {
			fail(`archive output must contain only regular files and directories: ${path.relative(root, absolute)}`)
		}
		const relative = path.relative(root, absolute).split(path.sep).join('/')
		if (relative.includes('\n') || relative.includes('\r')) {
			fail(`archive paths containing newlines are unsupported: ${JSON.stringify(relative)}`)
		}
		const extension = path.extname(relative).toLowerCase()
		if (forbiddenBinaryExtensions.has(extension)) {
			fail(`host/compiler-specific artifact is forbidden in the source package: ${relative}`)
		}
		files.push({ absolute, relative })
	}
}

/**
 * Normalizes package file metadata and writes the deterministic ZIP file list.
 * The archive stays source-level so it is not coupled to one OCaml compiler ABI.
 */
function finalizeArchive(values) {
	const root = path.resolve(requireValue(values, 'root'))
	const manifest = path.resolve(requireValue(values, 'manifest'))
	const epochSeconds = Number(values.epoch || defaultEpochSeconds)
	if (!Number.isInteger(epochSeconds) || epochSeconds < defaultEpochSeconds) {
		fail(`--epoch must be an integer at or after ${defaultEpochSeconds}`)
	}
	if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
		fail(`archive root is not a directory: ${root}`)
	}

	const files = []
	visitFiles(root, root, files)
	files.sort((left, right) => (left.relative < right.relative ? -1 : left.relative > right.relative ? 1 : 0))
	if (files.length === 0) {
		fail(`archive root contains no files: ${root}`)
	}

	const timestamp = new Date(epochSeconds * 1000)
	for (const file of files) {
		fs.chmodSync(file.absolute, 0o644)
		fs.utimesSync(file.absolute, timestamp, timestamp)
	}
	fs.mkdirSync(path.dirname(manifest), { recursive: true })
	fs.writeFileSync(manifest, files.map(file => file.relative).join('\n') + '\n')
	console.log(`[prepare-haxelib-archive] finalized ${files.length} source files`)
}

const { command, values } = parseArgs(process.argv.slice(2))
switch (command) {
	case 'stage':
		stageTrackedPackage(values)
		break
	case 'finalize':
		finalizeArchive(values)
		break
	default:
		fail('usage: prepare-haxelib-archive.js stage [--repo <dir>] --package <repo-relative-dir> --out <dir> | finalize --root <dir> --manifest <file> [--epoch <seconds>]')
}
