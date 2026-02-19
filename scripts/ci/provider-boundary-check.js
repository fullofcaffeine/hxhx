#!/usr/bin/env node
/**
 * provider-boundary-check.js
 *
 * Guardrail for the Stage3 backend provider boundary:
 * - keep the provider boundary cast isolated to BackendProviderResolver;
 * - avoid reintroducing reflective provider invocation on this path.
 *
 * Why
 * - OCaml bootstrap currently needs one scoped cast when bridging
 *   `ITargetBackendProvider` to a structural dispatch view.
 * - We intentionally keep this workaround in one place until interface-method
 *   dispatch is representable in this lane.
 */

const fs = require('fs')
const cp = require('child_process')

const allowedBoundaryFile = 'packages/hxhx/src/hxhx/BackendProviderResolver.hx'
const requiredBoundaryCast = /return\s+cast\s+providerContract\s*;/g
const forbiddenProviderReflection = /Reflect\.callMethod/g

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function gitTrackedAll() {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function readUtf8(path) {
  return fs.readFileSync(path, 'utf8')
}

function isCodeScope(path) {
  return path.startsWith('packages/hxhx/src/') || path.startsWith('packages/hxhx-core/src/')
}

function main() {
  const tracked = gitTrackedAll()
  const typedCastViolations = []

  for (const path of tracked) {
    if (!isCodeScope(path) || path === allowedBoundaryFile) continue
    let text = ''
    try {
      text = readUtf8(path)
    } catch (_) {
      continue
    }
    const hasProviderType = text.indexOf('ITargetBackendProvider') >= 0
    const hasCastKeyword = /\bcast\b/.test(text)
    if (hasProviderType && hasCastKeyword) {
      typedCastViolations.push(path)
    }
  }

  if (typedCastViolations.length > 0) {
    fail(
      'provider boundary cast must stay isolated to ' +
      `${allowedBoundaryFile}; found additional provider+cast usage in:\n- ${typedCastViolations.join('\n- ')}`
    )
  }

  let boundarySource = ''
  try {
    boundarySource = readUtf8(allowedBoundaryFile)
  } catch (_) {
    fail(`missing required provider boundary file: ${allowedBoundaryFile}`)
    return
  }

  const castMatches = boundarySource.match(requiredBoundaryCast) || []
  if (castMatches.length !== 1) {
    fail(
      `expected exactly one scoped provider boundary cast in ${allowedBoundaryFile}, found ${castMatches.length}`
    )
  }

  if (forbiddenProviderReflection.test(boundarySource)) {
    fail(`unexpected Reflect.callMethod usage in ${allowedBoundaryFile}`)
  }

  if (!process.exitCode) {
    console.log('[ci:guards] OK: provider boundary cast policy')
  }
}

main()
