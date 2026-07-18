#!/usr/bin/env node
/** Guards the one-package-builder, many-platform-consumers workflow boundary. */
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '../..')
const workflowPath = path.join(repoRoot, '.github/workflows/reflaxe-ocaml-package-matrix.yml')
const workflow = fs.readFileSync(workflowPath, 'utf8')

function fail(message) {
	console.error(`[reflaxe-ocaml-package-matrix-workflow-check] ERROR: ${message}`)
	process.exit(1)
}

function jobSection(name) {
	const marker = `\n  ${name}:\n`
	const start = workflow.indexOf(marker)
	if (start < 0) {
		fail(`missing job ${name}`)
	}
	const rest = workflow.slice(start + marker.length)
	const next = rest.search(/\n  [A-Za-z0-9_-]+:\n/)
	return next < 0 ? rest : rest.slice(0, next)
}

function requireIncludes(label, text, needle) {
	if (!text.includes(needle)) {
		fail(`${label} must include ${needle}`)
	}
}

const builder = jobSection('package_artifact')
const consumers = jobSection('package_install')
const summary = jobSection('package_matrix_summary')

for (const needle of [
	'name: Reflaxe OCaml / Package Artifact Matrix',
	'workflow_dispatch:',
	'schedule:',
	'cancel-in-progress: true'
]) {
	requireIncludes('workflow', workflow, needle)
}
for (const needle of [
	'npm run build:reflaxe-ocaml:package-artifact',
	'name: reflaxe-ocaml-source-package-${{ github.sha }}',
	'artifact-manifest.json',
	'if-no-files-found: error'
]) {
	requireIncludes('package_artifact', builder, needle)
}
for (const needle of [
	'needs: package_artifact',
	'fail-fast: false',
	'os: [ubuntu-latest, macos-latest]',
	'uses: actions/download-artifact@v4',
	'name: reflaxe-ocaml-source-package-${{ github.sha }}',
	'RO_PACKAGE_INSTALL_MANIFEST=',
	'RO_PACKAGE_INSTALL_ZIP=',
	'npm run test:reflaxe-ocaml:package-install',
	's.package.buildMode !== "supplied"',
	'RO_PACKAGE_ARTIFACT_CONSUMER:PASS'
]) {
	requireIncludes('package_install', consumers, needle)
}
if (consumers.includes('npm run build:reflaxe-ocaml:package-artifact')) {
	fail('platform consumers must not rebuild the package artifact')
}
for (const needle of [
	'needs: [package_artifact, package_install]',
	'pattern: reflaxe-ocaml-package-install-*-${{ github.sha }}',
	'reflaxe-ocaml-package-matrix-summary.js',
	'name: reflaxe-ocaml-package-matrix-${{ github.sha }}'
]) {
	requireIncludes('package_matrix_summary', summary, needle)
}

console.log('[ci:guards] OK: one reflaxe.ocaml package artifact feeds Linux and macOS consumers')
console.log('RO_PACKAGE_ARTIFACT_MATRIX_CONTRACT:PASS')
