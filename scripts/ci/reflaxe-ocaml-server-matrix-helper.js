#!/usr/bin/env node
/**
 * Small deterministic file helper for the real Reflaxe/Haxe-server matrix.
 *
 * Shell owns compiler and process orchestration. This helper owns structural
 * text replacement, manifest revision reads, and content-only tree digests so
 * the shell test does not accumulate inline source-patching programs.
 */
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

function fail(message) {
	throw new Error(message)
}

function replaceExactly(file, expected, replacement) {
	const source = fs.readFileSync(file, 'utf8')
	const occurrences = source.split(expected).length - 1
	if (occurrences !== 1) {
		fail(`expected exactly one ${JSON.stringify(expected)} in ${file}, found ${occurrences}`)
	}
	fs.writeFileSync(file, source.replace(expected, replacement))
}

function programRevision(manifestPath) {
	const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
	if (typeof manifest.programRevision !== 'string' || manifest.programRevision.length === 0) {
		fail(`artifact manifest has no programRevision: ${manifestPath}`)
	}
	process.stdout.write(manifest.programRevision)
}

function treeDigest(root) {
	const hash = crypto.createHash('sha256')
	const visit = (directory, prefix) => {
		const entries = fs.readdirSync(directory, {withFileTypes: true})
			.sort((left, right) => left.name < right.name ? -1 : (left.name > right.name ? 1 : 0))
		for (const entry of entries) {
			const relative = prefix === '' ? entry.name : `${prefix}/${entry.name}`
			const absolute = path.join(directory, entry.name)
			if (entry.isDirectory()) {
				visit(absolute, relative)
			} else if (entry.isFile()) {
				hash.update(Buffer.from(relative, 'utf8'))
				hash.update(Buffer.from([0]))
				hash.update(fs.readFileSync(absolute))
				hash.update(Buffer.from([0]))
			} else {
				fail(`unsupported tree entry in digest: ${absolute}`)
			}
		}
	}
	visit(root, '')
	process.stdout.write(`sha256:${hash.digest('hex')}`)
}

const [command, ...args] = process.argv.slice(2)
switch (command) {
	case 'replace':
		if (args.length !== 3) fail('replace needs: file expected replacement')
		replaceExactly(args[0], args[1], args[2])
		break
	case 'program-revision':
		if (args.length !== 1) fail('program-revision needs: manifest')
		programRevision(args[0])
		break
	case 'tree-digest':
		if (args.length !== 1) fail('tree-digest needs: directory')
		treeDigest(args[0])
		break
	default:
		fail(`unknown command: ${command || '<missing>'}`)
}
