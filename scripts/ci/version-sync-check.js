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
 * - LICENSE exists and looks like MIT
 */

const fs = require('fs')
const cp = require('child_process')

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

function gitTrackedUnder(path) {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z', '--', path], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    // In the unlikely event git isn't available, don't fail the build — this is a guardrail.
    return []
  }
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

  if (haxelib.license !== 'MIT') {
    fail(`haxelib.json license (${haxelib.license}) != MIT`)
  }

  if (!fs.existsSync('LICENSE')) {
    fail('LICENSE file missing at repo root')
  } else {
    const license = readUtf8('LICENSE')
    if (!license.includes('MIT License')) {
      fail('LICENSE does not look like MIT (missing header)')
    }
    if (!license.includes('Permission is hereby granted, free of charge')) {
      fail('LICENSE does not look like MIT (missing permission grant)')
    }
  }

  // Provenance/licensing guardrails:
  // - keep upstream Haxe checkouts untracked (we use vendor/haxe as a local oracle only).
  const trackedUpstream = gitTrackedUnder('vendor/haxe')
  if (trackedUpstream.length > 0) {
    fail(`Upstream Haxe checkout must not be committed (tracked files under vendor/haxe):\n- ${trackedUpstream.slice(0, 20).join('\n- ')}${trackedUpstream.length > 20 ? `\n- ... (${trackedUpstream.length} files total)` : ''}`)
  }

  if (process.exitCode) return
  console.log(`[ci:guards] OK: version ${version}`)
}

main()
