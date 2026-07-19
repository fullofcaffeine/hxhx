#!/usr/bin/env node
/** Exercises package artifact identity, source-only, and manifest checks. */
const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const {
	createArtifactManifest,
	inspectPackageArchive,
	validateArtifactManifest
} = require('./reflaxe-ocaml-package-artifact')

const metadata = { name: 'reflaxe.ocaml', version: '1.2.3', main: 'reflaxe.ocaml.tooling.ReflaxeOcamlRun' }

function createArchive(root, embeddedMetadata = metadata, extraFiles = {}) {
	const source = path.join(root, 'source')
	fs.mkdirSync(path.join(source, 'src/reflaxe/ocaml'), { recursive: true })
	fs.writeFileSync(path.join(source, 'haxelib.json'), JSON.stringify(embeddedMetadata))
	fs.writeFileSync(path.join(source, 'extraParams.hxml'), '-D ocaml\n')
	fs.mkdirSync(path.join(source, 'src/reflaxe/ocaml/tooling'), { recursive: true })
	fs.writeFileSync(path.join(source, 'src/reflaxe/ocaml/tooling/ReflaxeOcamlRun.hx'), 'class ReflaxeOcamlRun {}\n')
	fs.writeFileSync(path.join(source, 'src/reflaxe/ocaml/tooling/ReflaxeOcamlInspection.hx'), 'class ReflaxeOcamlInspection {}\n')
	fs.writeFileSync(path.join(source, 'src/reflaxe/ocaml/tooling/InspectionReport.hx'), 'typedef InspectionReport = {};\n')
	fs.writeFileSync(path.join(source, 'src/reflaxe/ocaml/OcamlCompiler.hx'), 'class OcamlCompiler {}\n')
	fs.mkdirSync(path.join(source, 'templates/scaffold/app'), { recursive: true })
	fs.mkdirSync(path.join(source, 'templates/scaffold/library'), { recursive: true })
	fs.writeFileSync(path.join(source, 'templates/scaffold/app/build.hxml'), '-main Main\n')
	fs.writeFileSync(path.join(source, 'templates/scaffold/library/build.hxml'), '-main LibraryBuild\n')
	for (const [relative, contents] of Object.entries(extraFiles)) {
		const destination = path.join(source, relative)
		fs.mkdirSync(path.dirname(destination), { recursive: true })
		fs.writeFileSync(destination, contents)
	}
	const zipPath = path.join(root, `${metadata.name}-${metadata.version}.zip`)
	const files = []
	function visit(directory) {
		for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
			const absolute = path.join(directory, entry.name)
			if (entry.isDirectory()) {
				visit(absolute)
			} else {
				files.push(path.relative(source, absolute).split(path.sep).join('/'))
			}
		}
	}
	visit(source)
	files.sort()
	const result = cp.spawnSync('zip', ['-X', '-q', zipPath, ...files], { cwd: source, encoding: 'utf8', shell: false })
	assert.strictEqual(result.status, 0, result.stderr)
	return zipPath
}

function mustReject(label, fn, needle) {
	assert.throws(fn, error => String(error.message).includes(needle), label)
}

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-ocaml-package-artifact-fixture-'))
try {
	const goodRoot = path.join(tempRoot, 'good')
	fs.mkdirSync(goodRoot)
	const goodZip = createArchive(goodRoot)
	const packageInfo = inspectPackageArchive(goodZip, metadata)
	const commit = 'a'.repeat(40)
	const manifest = createArtifactManifest(packageInfo, {
		implementationCommit: commit,
		workingTreeDirty: false,
		reproducible: true
	})
	validateArtifactManifest(manifest, packageInfo, commit)

	const wrongName = path.join(goodRoot, 'wrong-name.zip')
	fs.copyFileSync(goodZip, wrongName)
	mustReject('wrong filename must fail', () => inspectPackageArchive(wrongName, metadata), 'filename')

	const wrongVersionRoot = path.join(tempRoot, 'wrong-version')
	fs.mkdirSync(wrongVersionRoot)
	const wrongVersionZip = createArchive(wrongVersionRoot, { name: metadata.name, version: '9.9.9' })
	mustReject('embedded version must fail', () => inspectPackageArchive(wrongVersionZip, metadata), 'embedded package identity')

	const wrongHashManifest = JSON.parse(JSON.stringify(manifest))
	wrongHashManifest.package.sha256 = '0'.repeat(64)
	mustReject('wrong hash must fail', () => validateArtifactManifest(wrongHashManifest, packageInfo, commit), 'sha256')

	const forbiddenRoot = path.join(tempRoot, 'forbidden')
	fs.mkdirSync(forbiddenRoot)
	const forbiddenZip = createArchive(forbiddenRoot, metadata, { 'src/compiler-output.cmo': 'forbidden' })
	mustReject('compiler artifact must fail', () => inspectPackageArchive(forbiddenZip, metadata), 'compiler/host-specific artifact')

	console.log('REFLAXE_OCAML_PACKAGE_ARTIFACT_FIXTURE:PASS')
} finally {
	fs.rmSync(tempRoot, { recursive: true, force: true })
}
