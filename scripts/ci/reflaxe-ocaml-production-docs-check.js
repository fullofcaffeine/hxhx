#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const repoRoot = process.cwd()
const contractPath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md')
const guidePath = path.join(repoRoot, 'docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md')
const upstreamGuidePath = path.join(repoRoot, 'docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md')
const hxhxGuidePath = path.join(repoRoot, 'docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md')
const compilationServerGuidePath = path.join(repoRoot, 'docs/01-getting-started/COMPILATION_SERVER.md')
const startHerePath = path.join(repoRoot, 'docs/01-getting-started/START_HERE.md')
const docsIndexPath = path.join(repoRoot, 'docs/README.md')
const packageReadmePath = path.join(repoRoot, 'packages/reflaxe.ocaml/README.md')

function fail(message) {
  console.error(`[reflaxe-ocaml-production-docs-check] ERROR: ${message}`)
  process.exit(1)
}

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function requireIncludes(text, needle, label) {
  if (!text.includes(needle)) {
    fail(`${label} must include ${needle}`)
  }
}

function main() {
  const contract = read(contractPath)
  const guide = read(guidePath)
  const upstreamGuide = read(upstreamGuidePath)
  const hxhxGuide = read(hxhxGuidePath)
  const compilationServerGuide = read(compilationServerGuidePath)
  const startHere = read(startHerePath)
  const docsIndex = read(docsIndexPath)
  const packageReadme = read(packageReadmePath)

  requireIncludes(contract, 'RO_PRODUCTION_DOCS:PASS', contractPath)
  requireIncludes(contract, 'RO_PRODUCTION_READY:PASS', contractPath)
  requireIncludes(contract, 'test:reflaxe-ocaml:production-ready', contractPath)
  requireIncludes(contract, 'test:reflaxe-ocaml:package-install', contractPath)
  requireIncludes(contract, 'RO_PACKAGE_ARTIFACT_MATRIX:PASS', contractPath)
  requireIncludes(contract, 'reflaxe-ocaml-package-matrix.yml', contractPath)
  requireIncludes(contract, 'REFLAXE_OCAML_PRODUCTION.md', contractPath)

  requireIncludes(guide, 'RO_PRODUCTION_DOCS:PASS', guidePath)
  requireIncludes(guide, 'RO_PRODUCTION_READY:PASS', guidePath)
  requireIncludes(guide, 'haxe 4.3.7', guidePath)
  requireIncludes(guide, 'RO_HAXE_4_3_7_MATRIX:PASS', guidePath)
  requireIncludes(guide, 'RO_RUNTIME_STDLIB_CLOSURE:PASS', guidePath)
  requireIncludes(guide, 'RO_TARGET_PERF_CREDIBLE:PASS', guidePath)
  requireIncludes(guide, 'Type not found : reflaxe.ocaml', guidePath)
  requireIncludes(guide, 'ocaml_output', guidePath)
  requireIncludes(guide, 'dune / ocamlc not found', guidePath)
  requireIncludes(guide, 'Choosing between upstream `haxe + reflaxe.ocaml` and `hxhx`', guidePath)
  requireIncludes(guide, 'test:reflaxe-ocaml:package-install', guidePath)
  requireIncludes(guide, 'RO_PACKAGE_ARTIFACT_MATRIX:PASS', guidePath)
  requireIncludes(guide, 'verified-host evidence', guidePath)
  requireIncludes(guide, 'thin loader shells', guidePath)
  requireIncludes(guide, 'haxelib run reflaxe.ocaml new app', guidePath)
  requireIncludes(guide, 'haxelib run reflaxe.ocaml new library', guidePath)
  requireIncludes(guide, 'haxelib run reflaxe.ocaml inspect', guidePath)

  requireIncludes(upstreamGuide, 'REFLAXE_OCAML_PRODUCTION.md', upstreamGuidePath)
  requireIncludes(upstreamGuide, 'test:reflaxe-ocaml:package-install', upstreamGuidePath)
  requireIncludes(upstreamGuide, 'RO_PACKAGE_ARTIFACT_MATRIX:PASS', upstreamGuidePath)
  requireIncludes(upstreamGuide, 'haxelib run reflaxe.ocaml new app', upstreamGuidePath)
  requireIncludes(upstreamGuide, 'haxelib run reflaxe.ocaml new library', upstreamGuidePath)
  requireIncludes(upstreamGuide, 'haxelib run reflaxe.ocaml inspect', upstreamGuidePath)
  requireIncludes(upstreamGuide, 'COMPILATION_SERVER.md', upstreamGuidePath)
  requireIncludes(hxhxGuide, 'COMPILATION_SERVER.md', hxhxGuidePath)
  requireIncludes(compilationServerGuide, 'It is not enabled automatically', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'haxe --wait 6000', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'haxe --connect 6000 myproject.hxml', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'Safe `reflaxe.ocaml` application workflow', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'Safe `hxhx` development workflow', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'Editors and display clients', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'CI, containers, and remote development', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'haxe_ocaml-850ii.33', compilationServerGuidePath)
  requireIncludes(compilationServerGuide, 'There is intentionally no recommended native `hxhx` server setup command', compilationServerGuidePath)
  requireIncludes(startHere, 'REFLAXE_OCAML_PRODUCTION.md', startHerePath)
  requireIncludes(startHere, 'COMPILATION_SERVER.md', startHerePath)
  requireIncludes(docsIndex, 'COMPILATION_SERVER.md', docsIndexPath)
  requireIncludes(packageReadme, 'REFLAXE_OCAML_PRODUCTION.md', packageReadmePath)
  requireIncludes(packageReadme, 'test:reflaxe-ocaml:package-install', packageReadmePath)
  requireIncludes(packageReadme, 'RO_PACKAGE_ARTIFACT_MATRIX:PASS', packageReadmePath)
  requireIncludes(packageReadme, 'haxelib run reflaxe.ocaml new app', packageReadmePath)
  requireIncludes(packageReadme, 'haxelib run reflaxe.ocaml new library', packageReadmePath)
  requireIncludes(packageReadme, 'haxelib run reflaxe.ocaml inspect', packageReadmePath)
  requireIncludes(packageReadme, 'COMPILATION_SERVER.md', packageReadmePath)

  console.log('[ci:guards] OK: reflaxe.ocaml production docs are present and wired to contract/evidence')
  console.log('RO_PRODUCTION_DOCS:PASS')
}

main()
