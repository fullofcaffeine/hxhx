#!/usr/bin/env node
/** Proves generated app/library projects are safe, complete, and natively buildable. */
const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const tempParent = path.join(repoRoot, '.tmp')
fs.mkdirSync(tempParent, {recursive: true})
const tempRoot = fs.mkdtempSync(path.join(tempParent, 'reflaxe-ocaml-scaffold-'))
const haxeArgs = [
	'-cp', 'packages/reflaxe.ocaml/src',
	'--macro', 'nullSafety("reflaxe.ocaml")',
	'--run', 'reflaxe.ocaml.tooling.ReflaxeOcamlRun'
]

function runCli(args) {
	return cp.spawnSync('haxe', haxeArgs.concat(args), {
		cwd: repoRoot,
		env: process.env,
		encoding: 'utf8',
		maxBuffer: 50 * 1024 * 1024,
		shell: false
	})
}

try {
	const appRoot = path.join(tempRoot, 'fixture-app')
	const createdApp = runCli(['new', 'app', appRoot, '--name', 'Fixture App'])
	assert.strictEqual(createdApp.status, 0, createdApp.stderr || createdApp.stdout)
	assert(createdApp.stdout.includes('REFLAXE_OCAML_SCAFFOLD:PASS kind=app'))
	assert(createdApp.stdout.includes('inspect --require-lowering'))
	assert(fs.readFileSync(path.join(appRoot, 'src/Main.hx'), 'utf8').includes('Hello from Fixture App via reflaxe.ocaml!'))
	assert(fs.readFileSync(path.join(appRoot, 'README.md'), 'utf8').includes('inspect --require-lowering'))

	const editedMain = fs.readFileSync(path.join(appRoot, 'src/Main.hx'), 'utf8') + '// user edit\n'
	fs.writeFileSync(path.join(appRoot, 'src/Main.hx'), editedMain)
	const refusedOverwrite = runCli(['new', 'app', appRoot])
	assert.strictEqual(refusedOverwrite.status, 2)
	assert(refusedOverwrite.stderr.includes('Destination already exists'))
	assert.strictEqual(fs.readFileSync(path.join(appRoot, 'src/Main.hx'), 'utf8'), editedMain)

	const invalidNameRoot = path.join(tempRoot, 'invalid-name')
	const invalidName = runCli(['new', 'app', invalidNameRoot, '--name', '9 invalid'])
	assert.strictEqual(invalidName.status, 2)
	assert(invalidName.stderr.includes('Project names must start with a letter'))
	assert(!fs.existsSync(invalidNameRoot))

	const packageDestination = path.join(repoRoot, 'packages/reflaxe.ocaml/scaffold-must-not-exist')
	const refusedPackageMutation = runCli(['new', 'app', packageDestination, '--name', 'Unsafe Destination'])
	assert.strictEqual(refusedPackageMutation.status, 2)
	assert(refusedPackageMutation.stderr.includes('inside the installed reflaxe.ocaml package'))
	assert(!fs.existsSync(packageDestination))

	const appBuild = runCli([
		'build', '--project', appRoot,
		'--run', 'out/_build/default/out.exe'
	])
	assert.strictEqual(appBuild.status, 0, appBuild.stderr || appBuild.stdout)
	assert(appBuild.stdout.includes('Hello from Fixture App via reflaxe.ocaml!'))
	assert(appBuild.stdout.includes('REFLAXE_OCAML_BUILD:PASS'))
	assert(appBuild.stdout.includes('REFLAXE_OCAML_NATIVE_TIMING:PRESENT'))
	assert(appBuild.stdout.includes('typecheck + compile + link combined'))
	assert(appBuild.stdout.includes('REFLAXE_OCAML_RUN:PASS'))
	const appInspect = runCli(['inspect', '--project', appRoot, '--output', 'out', '--require-lowering', '--json'])
	assert.strictEqual(appInspect.status, 0, appInspect.stderr || appInspect.stdout)
	const appInspection = JSON.parse(appInspect.stdout)
	assert.strictEqual(appInspection.schemaVersion, 7)
	assert.strictEqual(appInspection.summary.valid, true)
	assert.strictEqual(appInspection.artifactManifest.status, 'present')
	assert.strictEqual(appInspection.artifactManifest.completeForSourceBundle, false)
	assert.strictEqual(appInspection.artifactManifest.blockers.length, 2)
	assert.strictEqual(appInspection.buildTiming.status, 'present')
	assert.strictEqual(appInspection.buildTiming.buildStatus, 'passed')
	assert.strictEqual(appInspection.buildTiming.nativeBuildRan, true)
	assert(appInspection.buildTiming.duneBuildMilliseconds >= 0)
	assert.deepStrictEqual(appInspection.buildTiming.duneBuildIncludes, ['typecheck', 'compile', 'link'])
	assert.strictEqual(appInspection.buildTiming.duneCacheHitsMeasured, false)
	assert.strictEqual(appInspection.lowering.status, 'present')
	assert.strictEqual(appInspection.representation.status, 'present')
	assert.strictEqual(appInspection.representation.scope, 'exact-int-bool-array-int-and-nullable-primitive-locals-v6')
	assert(appInspection.summary.representationDecisionCount > 0)
	assert.strictEqual(appInspection.lowering.staticStorage.length, appInspection.summary.staticStorageCount)
	assert(!appInspection.unavailable.some(capability => capability.id === 'program-representation'))
	assert.strictEqual(appInspection.runtime.semanticManifest, false)

	const libraryRoot = path.join(tempRoot, 'fixture-library')
	const createdLibrary = runCli(['new', 'library', libraryRoot, '--name', 'Fixture Library'])
	assert.strictEqual(createdLibrary.status, 0, createdLibrary.stderr || createdLibrary.stdout)
	assert(createdLibrary.stdout.includes('REFLAXE_OCAML_SCAFFOLD:PASS kind=library'))
	assert.strictEqual(JSON.parse(fs.readFileSync(path.join(libraryRoot, 'haxelib.json'), 'utf8')).name, 'fixture-library')

	const libraryBuild = runCli(['build', '--project', libraryRoot])
	assert.strictEqual(libraryBuild.status, 0, libraryBuild.stderr || libraryBuild.stdout)
	assert(libraryBuild.stdout.includes('REFLAXE_OCAML_NATIVE_TIMING:PRESENT'))
	const libraryTiming = JSON.parse(fs.readFileSync(path.join(libraryRoot, 'out/ocaml_build_timing_report.json'), 'utf8'))
	assert.strictEqual(libraryTiming.duneLayout, 'library')
	assert.strictEqual(libraryTiming.target, '@all')
	const libraryInspectionResult = runCli(['inspect', '--project', libraryRoot, '--output', 'out', '--json'])
	assert.strictEqual(libraryInspectionResult.status, 0, libraryInspectionResult.stderr || libraryInspectionResult.stdout)
	const libraryInspection = JSON.parse(libraryInspectionResult.stdout)
	assert.strictEqual(libraryInspection.artifactManifest.status, 'present')
	assert(libraryInspection.artifactManifest.kindCounts.some(kind => kind.id === 'dune-stanza' && kind.count >= 2))
	const dune = fs.readFileSync(path.join(libraryRoot, 'out/dune'), 'utf8')
	assert(dune.includes('(library'))
	assert(!dune.includes('(executable'))
	assert(fs.existsSync(path.join(libraryRoot, 'out/_build/default/out.cmxa')))

	const bindingRoot = path.join(tempRoot, 'fixture-binding')
	const refusedBinding = runCli(['new', 'binding', bindingRoot])
	assert.strictEqual(refusedBinding.status, 2)
	assert(refusedBinding.stderr.includes('typed .mli import manifests'))
	assert(!fs.existsSync(bindingRoot))

	console.log('REFLAXE_OCAML_SCAFFOLD_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, {recursive: true, force: true})
}
