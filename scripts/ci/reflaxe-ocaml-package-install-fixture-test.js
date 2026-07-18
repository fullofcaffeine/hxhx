#!/usr/bin/env node
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { findNekoLibraryDirectories } = require('./run-reflaxe-ocaml-package-install')

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-install-fixture-'))
try {
	const versionRoot = path.join(root, 'versions/2.4.0-linux64')
	fs.mkdirSync(versionRoot, { recursive: true })
	fs.writeFileSync(path.join(versionRoot, 'libneko.so.2'), '')

	assert.deepStrictEqual(findNekoLibraryDirectories(root), [root, versionRoot])
	console.log('REFLAXE_OCAML_PACKAGE_INSTALL_FIXTURE:PASS')
} finally {
	fs.rmSync(root, { recursive: true, force: true })
}
