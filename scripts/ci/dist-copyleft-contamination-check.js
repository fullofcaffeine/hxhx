#!/usr/bin/env node
/**
 * dist-copyleft-contamination-check.js
 *
 * Release guard for distribution artifacts:
 * - scan dist payloads for obvious copyleft license markers;
 * - reject bundled reflaxe.elixir payload paths in MIT-focused dist layout.
 */

const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const defaultDistRoot = path.join(root, 'dist', 'hxhx')
const args = process.argv.slice(2)
let distRoot = defaultDistRoot

for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--dist-root') {
    const next = args[i + 1]
    if (!next) {
      console.error('[guard:dist-copyleft] ERROR: missing value for --dist-root')
      process.exit(1)
    }
    distRoot = path.resolve(next)
    i += 1
  }
}

const allowedTextExts = new Set([
  '.md',
  '.txt',
  '.json',
  '.hxml',
  '.hx',
  '.ml',
  '.mli',
  '.dune',
  '.js',
  '.cjs',
  '.sh',
  '.xml',
  '.yml',
  '.yaml',
  '.toml',
  '.ini',
  '.cfg',
  '.license',
  '.haxelib',
])

const copyleftAcronym = 'G' + 'PL'
const lesserCopyleftAcronym = 'L' + copyleftAcronym
const bannedContentRules = [
  { id: 'copyleft_full_text', re: /gnu general public license/i },
  { id: 'copyleft_license_field', re: new RegExp(`"license"\\s*:\\s*"${copyleftAcronym}[^"]*"`, 'i') },
  { id: 'copyleft_acronym_major', re: new RegExp(`\\b${copyleftAcronym}(?:-|\\s)?(?:2(?:\\.0)?|3(?:\\.0)?)\\b`, 'i') },
  { id: 'copyleft_acronym_lesser', re: new RegExp(`\\b${lesserCopyleftAcronym}(?:-|\\s)?(?:2(?:\\.1)?|3(?:\\.0)?)\\b`, 'i') },
]

const bannedPathRules = [
  { id: 'bundled_reflaxe_elixir', re: /(^|\/)lib\/reflaxe\.elixir(\/|$)/i },
]

function fail(message) {
  console.error(`[guard:dist-copyleft] ERROR: ${message}`)
  process.exitCode = 1
}

function walkFiles(dir, out) {
  const entries = fs.readdirSync(dir, { withFileTypes: true })
  for (const entry of entries) {
    const abs = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      walkFiles(abs, out)
      continue
    }
    if (entry.isFile()) {
      out.push(abs)
    }
  }
}

function isLikelyText(filePath) {
  const base = path.basename(filePath)
  if (base === 'LICENSE' || base === 'COPYING' || base === 'README' || base === 'CHANGELOG') {
    return true
  }
  return allowedTextExts.has(path.extname(filePath).toLowerCase())
}

function hasBinaryNulls(buffer) {
  const cap = Math.min(buffer.length, 8192)
  for (let i = 0; i < cap; i += 1) {
    if (buffer[i] === 0) {
      return true
    }
  }
  return false
}

function main() {
  if (!fs.existsSync(distRoot) || !fs.statSync(distRoot).isDirectory()) {
    fail(`dist root not found: ${distRoot} (build distribution first)`)
    return
  }

  const files = []
  walkFiles(distRoot, files)
  if (files.length === 0) {
    fail(`dist root has no files: ${distRoot}`)
    return
  }

  const violations = []
  for (const absPath of files) {
    const relPath = path.relative(root, absPath).split(path.sep).join('/')

    for (const rule of bannedPathRules) {
      if (rule.re.test(relPath)) {
        violations.push({ type: 'path', rule: rule.id, path: relPath })
      }
    }

    if (!isLikelyText(absPath)) {
      continue
    }

    let bytes = Buffer.alloc(0)
    try {
      bytes = fs.readFileSync(absPath)
    } catch (error) {
      violations.push({ type: 'read_error', path: relPath, detail: error.message })
      continue
    }

    if (hasBinaryNulls(bytes)) {
      continue
    }

    const text = bytes.toString('utf8')
    for (const rule of bannedContentRules) {
      if (rule.re.test(text)) {
        violations.push({ type: 'content', rule: rule.id, path: relPath })
      }
    }
  }

  if (violations.length > 0) {
    for (const v of violations) {
      if (v.type === 'content') {
        fail(`${v.rule} matched in ${v.path}`)
      } else if (v.type === 'path') {
        fail(`${v.rule} matched path ${v.path}`)
      } else {
        fail(`failed to read ${v.path}: ${v.detail}`)
      }
    }
    return
  }

  console.log(`[guard:dist-copyleft] OK: no copyleft contamination markers found in ${distRoot}`)
}

main()
