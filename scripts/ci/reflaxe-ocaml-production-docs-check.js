#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const repoRoot = process.cwd()
const contractPath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md')
const guidePath = path.join(repoRoot, 'docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md')
const upstreamGuidePath = path.join(repoRoot, 'docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md')
const startHerePath = path.join(repoRoot, 'docs/01-getting-started/START_HERE.md')
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
  const startHere = read(startHerePath)
  const packageReadme = read(packageReadmePath)

  requireIncludes(contract, 'RO_PRODUCTION_DOCS:PASS', contractPath)
  requireIncludes(contract, 'RO_PRODUCTION_READY:PASS', contractPath)
  requireIncludes(contract, 'test:reflaxe-ocaml:production-ready', contractPath)
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

  requireIncludes(upstreamGuide, 'REFLAXE_OCAML_PRODUCTION.md', upstreamGuidePath)
  requireIncludes(startHere, 'REFLAXE_OCAML_PRODUCTION.md', startHerePath)
  requireIncludes(packageReadme, 'REFLAXE_OCAML_PRODUCTION.md', packageReadmePath)

  console.log('[ci:guards] OK: reflaxe.ocaml production docs are present and wired to contract/evidence')
  console.log('RO_PRODUCTION_DOCS:PASS')
}

main()
