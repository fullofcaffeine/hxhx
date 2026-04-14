#!/usr/bin/env node
const fs = require('fs')

const files = {
  contract: 'docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md',
  tradeoffs: 'docs/00-project/REFLAXE_PROMOTION_MATRIX_TRADEOFFS.md',
  choose: 'docs/01-getting-started/CHOOSE_A_REFLAXE_PROMOTION_PATH.md',
  startHere: 'docs/01-getting-started/START_HERE.md',
  docsReadme: 'docs/README.md',
  packageJson: 'package.json',
}

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function read(path) {
  if (!fs.existsSync(path)) {
    fail(`missing required file: ${path}`)
    return ''
  }
  return fs.readFileSync(path, 'utf8')
}

function requireIncludes(path, text, snippet) {
  if (!text.includes(snippet)) fail(`${path} must include: ${snippet}`)
}

function requireScriptTarget(pkg, key) {
  const script = pkg.scripts && pkg.scripts[key]
  if (!script) {
    fail(`package.json missing script: ${key}`)
    return
  }
  const match = script.match(/\b(?:bash|node)\s+([^\s;&|]+)/)
  if (!match) {
    fail(`package script ${key} must call a local bash/node target`)
    return
  }
  if (!fs.existsSync(match[1])) {
    fail(`package script ${key} points at missing file: ${match[1]}`)
  }
}

function main() {
  const contract = read(files.contract)
  const tradeoffs = read(files.tradeoffs)
  const choose = read(files.choose)
  const startHere = read(files.startHere)
  const docsReadme = read(files.docsReadme)
  const pkgText = read(files.packageJson)
  const pkg = pkgText ? JSON.parse(pkgText) : { scripts: {} }

  requireIncludes(files.contract, contract, 'RO_PROMOTION_MATRIX:PASS')
  requireIncludes(files.tradeoffs, tradeoffs, 'Aggregate status: not claimable yet')
  requireIncludes(files.tradeoffs, tradeoffs, 'RPMX_HXHX_BUILTIN:BLOCKED')
  requireIncludes(files.tradeoffs, tradeoffs, 'RPMX_HXHX_PLUGIN:PASS')
  requireIncludes(files.choose, choose, 'Default recommendation')
  requireIncludes(files.choose, choose, 'official external native path')
  requireIncludes(files.startHere, startHere, 'CHOOSE_A_REFLAXE_PROMOTION_PATH.md')
  requireIncludes(files.docsReadme, docsReadme, 'CHOOSE_A_REFLAXE_PROMOTION_PATH.md')
  requireIncludes(files.docsReadme, docsReadme, 'REFLAXE_PROMOTION_MATRIX_TRADEOFFS.md')

  requireScriptTarget(pkg, 'test:rpmx:haxe-plugin')
  requireScriptTarget(pkg, 'test:rpmx:hxhx-builtin')
  requireScriptTarget(pkg, 'test:rpmx:hxhx-plugin')
  requireScriptTarget(pkg, 'test:rpmx:hxhx-plugin-host-pilot')

  if (process.exitCode) return
  console.log('[ci:guards] OK: promotion matrix docs and script targets are wired')
  console.log('RO_PROMOTION_MATRIX_DOCS:PASS')
}

main()
