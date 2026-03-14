#!/usr/bin/env node
const fs = require('fs')

const auditDocPath = 'docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.md'
const auditJsonPath = 'docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.json'
const contractDocPath = 'docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md'

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function exists(filePath) {
  return fs.existsSync(filePath)
}

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function requirePath(filePath) {
  if (!exists(filePath)) {
    fail(`missing required path: ${filePath}`)
    return false
  }
  return true
}

function main() {
  if (!requirePath(auditDocPath)) return
  if (!requirePath(auditJsonPath)) return
  if (!requirePath(contractDocPath)) return

  const contractDoc = readUtf8(contractDocPath)
  if (!contractDoc.includes('RO_RUNTIME_STDLIB_CLOSURE:PASS')) {
    fail(`${contractDocPath} must reference RO_RUNTIME_STDLIB_CLOSURE:PASS`)
  }

  const auditDoc = readUtf8(auditDocPath)
  if (!auditDoc.includes(auditJsonPath)) {
    fail(`${auditDocPath} must reference ${auditJsonPath}`)
  }

  let audit = null
  try {
    audit = JSON.parse(readUtf8(auditJsonPath))
  } catch (error) {
    fail(`invalid JSON in ${auditJsonPath}: ${error.message}`)
    return
  }

  if (audit.haxeCompatibilityBaseline !== '4.3.7') {
    fail(`audit baseline must be 4.3.7 (received: ${audit.haxeCompatibilityBaseline})`)
  }
  if (!Array.isArray(audit.allowedStatuses) || audit.allowedStatuses.length === 0) {
    fail('audit JSON must define allowedStatuses[]')
  }
  if (!Array.isArray(audit.entries) || audit.entries.length === 0) {
    fail('audit JSON must define entries[]')
    return
  }

  const allowed = new Set(audit.allowedStatuses)
  for (const entry of audit.entries) {
    if (!entry.id || !entry.title || !entry.status || !entry.summary) {
      fail(`audit entry is missing required fields: ${JSON.stringify(entry)}`)
      continue
    }
    if (!allowed.has(entry.status)) {
      fail(`audit entry ${entry.id} has unsupported status ${entry.status}`)
    }
    if (!Array.isArray(entry.references) || entry.references.length === 0) {
      fail(`audit entry ${entry.id} must define references[]`)
      continue
    }
    for (const ref of entry.references) {
      if (!exists(ref)) {
        fail(`audit entry ${entry.id} references missing path ${ref}`)
      }
    }
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: reflaxe.ocaml runtime/stdlib closure audit is valid')
  console.log('RO_RUNTIME_STDLIB_CLOSURE:PASS')
}

main()
