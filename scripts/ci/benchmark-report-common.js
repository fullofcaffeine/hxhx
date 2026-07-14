/**
 * Small, target-neutral helpers shared by self-describing benchmark reports.
 *
 * This module owns data-shape facts such as SHA validation, medians, safe
 * evidence paths, and tool-version lookup. Each benchmark keeps its own rules
 * about what was measured and what counts as passing evidence.
 */

const childProcess = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0
}

function isSha(value) {
  return /^[0-9a-f]{40}$/i.test(value || '')
}

function isDigest(value) {
  return /^[0-9a-f]{64}$/i.test(value || '')
}

function isIsoTimestamp(value) {
  if (!nonEmptyString(value)) return false
  const parsed = Date.parse(value)
  return !Number.isNaN(parsed) && new Date(parsed).toISOString() === value
}

function isNormalizedPath(value) {
  return nonEmptyString(value)
    && !path.isAbsolute(value)
    && !/^[A-Za-z]:[\\/]/.test(value)
    && !value.startsWith('~')
    && !value.split(/[\\/]/).includes('..')
}

function parseBoolean(value, label) {
  if (value === true || value === 'true' || value === '1' || value === 1) return true
  if (value === false || value === 'false' || value === '0' || value === 0) return false
  throw new Error(`${label} must be true/false or 1/0`)
}

function parseInteger(value, label, minimum = 0) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed < minimum) {
    throw new Error(`${label} must be an integer >= ${minimum}`)
  }
  return parsed
}

function median(values) {
  const ordered = [...values].sort((left, right) => left - right)
  const middle = Math.floor(ordered.length / 2)
  if (ordered.length % 2 === 1) return ordered[middle]
  return (ordered[middle - 1] + ordered[middle]) / 2
}

function numericSummary(values) {
  return {
    count: values.length,
    min: Math.min(...values),
    max: Math.max(...values),
    median: median(values),
    samples: [...values]
  }
}

function round(value, places) {
  const scale = 10 ** places
  return Math.round(value * scale) / scale
}

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function directoryDigest(directoryPath, ignoredNames = new Set(['_build'])) {
  const root = path.resolve(directoryPath)
  const files = []
  function visit(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (ignoredNames.has(entry.name)) continue
      const entryPath = path.join(current, entry.name)
      if (entry.isDirectory()) visit(entryPath)
      else if (entry.isFile()) files.push(entryPath)
      else throw new Error(`unsupported entry while hashing ${directoryPath}: ${entryPath}`)
    }
  }
  visit(root)
  files.sort()
  const hash = crypto.createHash('sha256')
  let bytes = 0
  for (const filePath of files) {
    const relative = path.relative(root, filePath).split(path.sep).join('/')
    const contents = fs.readFileSync(filePath)
    hash.update(relative)
    hash.update('\0')
    hash.update(contents)
    hash.update('\0')
    bytes += contents.length
  }
  return {
    sha256: hash.digest('hex'),
    file_count: files.length,
    byte_count: bytes
  }
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    throw new Error(`could not read ${label} ${filePath}: ${error.message}`)
  }
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

function runTool(command, args, label, cwd) {
  const result = childProcess.spawnSync(command, args, {
    cwd,
    encoding: 'utf8'
  })
  if (result.status !== 0) {
    throw new Error(`could not read ${label} from ${command}: ${(result.stderr || result.stdout || '').trim()}`)
  }
  const output = `${result.stdout || ''}\n${result.stderr || ''}`.trim().split(/\r?\n/)[0]
  if (!output) throw new Error(`${label} output was empty`)
  return output
}

function normalizeToolLabel(value, repoRoot) {
  if (!nonEmptyString(value)) return 'unknown'
  if (!path.isAbsolute(value)) return value
  const relative = path.relative(repoRoot, value)
  if (relative && !relative.startsWith('..') && !path.isAbsolute(relative)) {
    return relative.split(path.sep).join('/')
  }
  return path.basename(value)
}

module.exports = {
  directoryDigest,
  isDigest,
  isIsoTimestamp,
  isNormalizedPath,
  isSha,
  median,
  nonEmptyString,
  normalizeToolLabel,
  numericSummary,
  parseBoolean,
  parseInteger,
  readJson,
  round,
  runTool,
  sameJson,
  sha256
}
