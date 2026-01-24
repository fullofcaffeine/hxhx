#!/usr/bin/env node
/**
 * version-sync-check.js
 *
 * Guardrail for CI: ensure versions are consistent across repo entrypoints.
 *
 * Checks:
 * - package.json version
 * - package-lock.json version (+ packages[""].version)
 * - haxelib.json version
 * - haxe_libraries/reflaxe.ocaml.hxml (-D reflaxe.ocaml=...)
 * - LICENSE exists and looks like GPLv3
 */

const fs = require('fs')

function readUtf8(path) {
  return fs.readFileSync(path, 'utf8')
}

function readJson(path) {
  return JSON.parse(readUtf8(path))
}

function fail(msg) {
  console.error(`[ci:guards] ERROR: ${msg}`)
  process.exitCode = 1
}

function extractHxmlDefine(path, defineName) {
  const text = readUtf8(path)
  const escaped = defineName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const re = new RegExp(`^-D\\s+${escaped}=([^\\s]+)\\s*$`, 'm')
  const m = text.match(re)
  return m ? m[1] : null
}

function main() {
  const pkg = readJson('package.json')
  const lock = readJson('package-lock.json')
  const haxelib = readJson('haxelib.json')
  const hxmlVersion = extractHxmlDefine('haxe_libraries/reflaxe.ocaml.hxml', 'reflaxe.ocaml')

  const version = pkg.version
  if (!version) {
    fail('package.json is missing "version"')
    return
  }

  if (lock.version !== version) {
    fail(`package-lock.json version (${lock.version}) != package.json version (${version})`)
  }

  const lockRoot = lock.packages && lock.packages[''] && lock.packages[''].version
  if (lockRoot && lockRoot !== version) {
    fail(`package-lock.json packages[""].version (${lockRoot}) != package.json version (${version})`)
  }

  if (haxelib.version !== version) {
    fail(`haxelib.json version (${haxelib.version}) != package.json version (${version})`)
  }

  if (!hxmlVersion) {
    fail('haxe_libraries/reflaxe.ocaml.hxml is missing -D reflaxe.ocaml=...')
  } else if (hxmlVersion !== version) {
    fail(`haxe_libraries/reflaxe.ocaml.hxml reflaxe.ocaml define (${hxmlVersion}) != package.json version (${version})`)
  }

  if (haxelib.license !== 'GPL-3.0') {
    fail(`haxelib.json license (${haxelib.license}) != GPL-3.0`)
  }

  if (!fs.existsSync('LICENSE')) {
    fail('LICENSE file missing at repo root')
  } else {
    const license = readUtf8('LICENSE')
    if (!license.includes('GNU GENERAL PUBLIC LICENSE')) {
      fail('LICENSE does not look like GNU GPL (missing header)')
    }
    if (!license.includes('Version 3, 29 June 2007')) {
      fail('LICENSE does not look like GPLv3 (missing version header)')
    }
  }

  if (process.exitCode) return
  console.log(`[ci:guards] OK: version ${version}`)
}

main()
