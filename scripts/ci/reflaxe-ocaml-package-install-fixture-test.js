#!/usr/bin/env node
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { findNekoLibraryDirectories, performanceEnvironment } = require('./run-reflaxe-ocaml-package-install')

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-install-fixture-'))
try {
	const versionRoot = path.join(root, 'versions/2.4.0-linux64')
	fs.mkdirSync(versionRoot, { recursive: true })
	fs.writeFileSync(path.join(versionRoot, 'libneko.so.2'), '')

	assert.deepStrictEqual(findNekoLibraryDirectories(root), [root, versionRoot])
	assert.deepStrictEqual(performanceEnvironment({
		HAXELIB_PATH: '/isolated/haxelib',
		HAXE_STD_PATH: '/compiler/std',
		PATH: '/compiler/bin',
		GITHUB_TOKEN: 'must-not-leak',
		UNRELATED_VALUE: 'must-not-leak'
	}), {
		HAXELIB_PATH: '/isolated/haxelib',
		HAXE_STD_PATH: '/compiler/std',
		PATH: '/compiler/bin'
	})
	console.log('REFLAXE_OCAML_PACKAGE_INSTALL_FIXTURE:PASS')
} finally {
	fs.rmSync(root, { recursive: true, force: true })
}
