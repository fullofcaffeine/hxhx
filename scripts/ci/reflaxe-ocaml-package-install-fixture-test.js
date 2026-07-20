#!/usr/bin/env node
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { findNekoLibraryDirectories, performanceEnvironment, sha256Directory, validateInstalledDoctor } = require('./run-reflaxe-ocaml-package-install')

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-install-fixture-'))
try {
	const versionRoot = path.join(root, 'versions/2.4.0-linux64')
	fs.mkdirSync(versionRoot, { recursive: true })
	fs.writeFileSync(path.join(versionRoot, 'libneko.so.2'), '')

	assert.deepStrictEqual(findNekoLibraryDirectories(root), [root, versionRoot])

	const digestRootA = path.join(root, 'digest-a')
	const digestRootB = path.join(root, 'digest-b')
	fs.mkdirSync(path.join(digestRootA, 'src'), { recursive: true })
	fs.mkdirSync(path.join(digestRootB, 'src'), { recursive: true })
	fs.writeFileSync(path.join(digestRootA, 'Run.hx'), 'class Run {}\n')
	fs.writeFileSync(path.join(digestRootA, 'src/Value.hx'), 'class Value {}\n')
	fs.writeFileSync(path.join(digestRootB, 'src/Value.hx'), 'class Value {}\n')
	fs.writeFileSync(path.join(digestRootB, 'Run.hx'), 'class Run {}\n')
	assert.strictEqual(sha256Directory(digestRootA), sha256Directory(digestRootB))
	fs.appendFileSync(path.join(digestRootB, 'Run.hx'), '// changed\n')
	assert.notStrictEqual(sha256Directory(digestRootA), sha256Directory(digestRootB))

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
