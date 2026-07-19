#!/usr/bin/env node
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { findNekoLibraryDirectories, performanceEnvironment, validateInstalledDoctor } = require('./run-reflaxe-ocaml-package-install')

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-install-fixture-'))
try {
	// Haxe injects this helper into derived exception constructors after Reflaxe
	// preprocessing. Keeping it non-inline prevents a late field update from
	// bypassing the target-owned place-lowering origin on platform-only paths.
	const exceptionSource = fs.readFileSync(path.join(
		__dirname,
		'../../packages/reflaxe.ocaml/std/ocaml/_std/haxe/Exception.hx'
	), 'utf8')
	assert.match(exceptionSource, /\n\tfunction __shiftStack\(\):Void \{/)
	assert.match(exceptionSource, /\n\tfunction __unshiftStack\(\):Void \{/)
	assert.doesNotMatch(exceptionSource, /inline function __(?:un)?shiftStack/)

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
	assert.deepStrictEqual(validateInstalledDoctor({
		schemaVersion: 1,
		packageName: 'reflaxe.ocaml',
		packageVersion: '1.2.3',
		summary: {requestedCapability: 'native', ready: true, exitCode: 0},
		capabilities: {sourceGeneration: true, nativeBuild: true}
	}, '1.2.3'), {
		doctorPassed: true,
		doctorSchemaVersion: 1,
		sourceGenerationReady: true,
		nativeBuildReady: true
	})
	assert.throws(() => validateInstalledDoctor({
		schemaVersion: 1,
		packageName: 'reflaxe.ocaml',
		packageVersion: '1.2.3',
		summary: {requestedCapability: 'native', ready: false, exitCode: 1},
		capabilities: {sourceGeneration: true, nativeBuild: false}
	}, '1.2.3'), /did not confirm native capability/)
	console.log('REFLAXE_OCAML_PACKAGE_INSTALL_FIXTURE:PASS')
} finally {
	fs.rmSync(root, { recursive: true, force: true })
}
