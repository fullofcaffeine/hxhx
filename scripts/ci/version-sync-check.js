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

function gitTrackedAll() {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function shouldScanText(path) {
  // Skip bd issue-tracker state. This repo treats `.beads/` as development metadata, not distributable
  // source, and bd can legitimately contain historical discussion that we don't want to gate CI on.
  if (path.startsWith('.beads/')) return false

  // Keep this conservative: scan everything that is likely to be UTF-8 text.
  // Skip obvious binary-ish extensions.
  const lower = path.toLowerCase()
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.ico')) return false
  if (lower.endsWith('.pdf') || lower.endsWith('.zip') || lower.endsWith('.gz') || lower.endsWith('.tar') || lower.endsWith('.tgz')) return false
  if (lower.endsWith('.exe') || lower.endsWith('.bc') || lower.endsWith('.a') || lower.endsWith('.so') || lower.endsWith('.dylib')) return false
  return true
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

  // - keep common copyleft license markers out of the tracked source tree.
  //
  // Why
  // - This repo has an explicit goal of staying permissively-licensed, and we want to avoid
  //   accidentally committing upstream license texts or copyleft headers.
  //
  // What
  // - Fail if a tracked text file contains common copyleft markers.
  //
  // Note
  // - This is a lightweight string check, not a legal analysis tool.
  const copyleftAcronym = 'G' + 'PL'
  const forbiddenMarkers = [
    ['GNU', 'GENERAL', 'PUBLIC', 'LICENSE'].join(' '),
    copyleftAcronym,
    `${copyleftAcronym}-[0-9]`,
  ]
  const forbidden = [
    new RegExp(forbiddenMarkers[0], 'i'),
    new RegExp(`\\b${forbiddenMarkers[1]}\\b`, 'i'),
    new RegExp(forbiddenMarkers[2], 'i'),
  ]

  for (const path of gitTrackedAll()) {
    if (!shouldScanText(path)) continue
    let text
    try {
      text = readUtf8(path)
    } catch (_) {
      continue
    }
    for (const re of forbidden) {
      if (re.test(text)) {
        fail(`forbidden license marker found in tracked file: ${path} (matched ${re})`)
        break
      }
    }
    if (process.exitCode) break
  }

  if (process.exitCode) return
  console.log(`[ci:guards] OK: version ${version}`)
}

main()
