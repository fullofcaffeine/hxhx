#!/usr/bin/env node

const crypto = require('node:crypto')
const fs = require('node:fs')
const path = require('node:path')

const SCHEMA = 'hxhx.native-macro-module.v1'
const ABI_VERSION = 1
const MACRO_API_VERSION = 1

function fail(message) {
  process.stderr.write(`native-macro-module-receipt: ${message}\n`)
  process.exit(1)
}

function parseArgs(argv) {
  const command = argv[2]
  const values = new Map()
  for (let index = 3; index < argv.length; index += 2) {
    const key = argv[index]
    const value = argv[index + 1]
    if (!key || !key.startsWith('--') || value === undefined) {
      fail(`invalid arguments near ${key || '<end>'}`)
    }
    values.set(key.slice(2), value)
  }
  return { command, values }
}

function required(values, name) {
  const value = values.get(name)
  if (!value || value.trim().length === 0) fail(`--${name} is required`)
  return value.trim()
}

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function resolveContainedArtifact(reportPath, artifactValue) {
  const reportDirectory = path.dirname(reportPath)
  const artifactPath = path.resolve(reportDirectory, artifactValue)
  const relative = path.relative(reportDirectory, artifactPath)
  if (relative.length === 0 || relative.startsWith(`..${path.sep}`) || relative === '..' || path.isAbsolute(relative)) {
    fail('artifact path must name a file inside the receipt directory')
  }
  return artifactPath
}

function validateArtifact(reportPath, artifact, kind) {
  if (!artifact || !artifact.path || !artifact.sha256) fail(`artifacts.${kind} path and sha256 are required`)
  const artifactPath = resolveContainedArtifact(reportPath, artifact.path)
  if (!fs.existsSync(artifactPath) || !fs.statSync(artifactPath).isFile()) fail(`${kind} artifact not found: ${artifactPath}`)
  const actualDigest = sha256(artifactPath)
  if (actualDigest !== artifact.sha256) {
    fail(`${kind} artifact SHA-256 mismatch: receipt=${artifact.sha256} actual=${actualDigest}`)
  }
  return { artifactPath, actualDigest }
}

function validateReceipt(reportPath, expectedCandidate) {
  if (!fs.existsSync(reportPath) || !fs.statSync(reportPath).isFile()) fail(`receipt not found: ${reportPath}`)
  let receipt
  try {
    receipt = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
  } catch (error) {
    fail(`invalid JSON in ${reportPath}: ${error.message}`)
  }
  if (!receipt || receipt.schema !== SCHEMA) fail(`unsupported schema: ${receipt?.schema || '<missing>'}`)
  if (!receipt.candidateCommit) fail('candidateCommit is required')
  if (expectedCandidate && receipt.candidateCommit !== expectedCandidate) {
    fail(`candidate mismatch: receipt=${receipt.candidateCommit} expected=${expectedCandidate}`)
  }
  if (!receipt.pluginId) fail('pluginId is required')
  if (receipt.abiVersion !== ABI_VERSION) fail(`abiVersion mismatch: ${receipt.abiVersion}`)
  if (receipt.macroApiVersion !== MACRO_API_VERSION) fail(`macroApiVersion mismatch: ${receipt.macroApiVersion}`)
  if (!Array.isArray(receipt.expressions) || receipt.expressions.length !== 1 || !receipt.expressions[0]) {
    fail('this pilot requires exactly one expression')
  }
  if (!receipt.artifacts) fail('artifacts is required')
  const native = validateArtifact(reportPath, receipt.artifacts.native, 'native')
  const bytecode = validateArtifact(reportPath, receipt.artifacts.bytecode, 'bytecode')
  return { receipt, native, bytecode }
}

function writeReceipt(values) {
  const reportPath = path.resolve(required(values, 'report'))
  const nativeArtifactPath = path.resolve(required(values, 'native-artifact'))
  const bytecodeArtifactPath = path.resolve(required(values, 'bytecode-artifact'))
  for (const artifactPath of [nativeArtifactPath, bytecodeArtifactPath]) {
    if (!fs.existsSync(artifactPath) || !fs.statSync(artifactPath).isFile()) fail(`artifact not found: ${artifactPath}`)
  }
  fs.mkdirSync(path.dirname(reportPath), { recursive: true })
  const relativeArtifact = (artifactPath) => {
    const relative = path.relative(path.dirname(reportPath), artifactPath)
    if (relative.startsWith(`..${path.sep}`) || relative === '..' || path.isAbsolute(relative)) {
      fail('artifacts must be inside the receipt directory')
    }
    return relative.split(path.sep).join('/')
  }
  const receipt = {
    schema: SCHEMA,
    candidateCommit: required(values, 'candidate-commit'),
    pluginId: required(values, 'plugin-id'),
    abiVersion: ABI_VERSION,
    macroApiVersion: MACRO_API_VERSION,
    expressions: [required(values, 'expr')],
    artifacts: {
      native: {
        path: relativeArtifact(nativeArtifactPath),
        sha256: sha256(nativeArtifactPath),
      },
      bytecode: {
        path: relativeArtifact(bytecodeArtifactPath),
        sha256: sha256(bytecodeArtifactPath),
      },
    },
  }
  fs.writeFileSync(reportPath, `${JSON.stringify(receipt, null, 2)}\n`)
  process.stdout.write(`${reportPath}\n`)
}

function mutateFixture(values) {
  const sourcePath = path.resolve(required(values, 'report'))
  const outputPath = path.resolve(required(values, 'out'))
  const kind = required(values, 'kind')
  const receipt = JSON.parse(fs.readFileSync(sourcePath, 'utf8'))
  if (kind === 'wrong-candidate') receipt.candidateCommit = 'definitely-another-candidate'
  else if (kind === 'wrong-abi') receipt.abiVersion = ABI_VERSION + 1
  else if (kind === 'wrong-native-digest') receipt.artifacts.native.sha256 = '0'.repeat(64)
  else if (kind === 'wrong-bytecode-digest') receipt.artifacts.bytecode.sha256 = '0'.repeat(64)
  else if (kind === 'wrong-expression') receipt.expressions = ['projectmacro.ProjectMacro.missing()']
  else if (kind === 'missing-native') receipt.artifacts.native.path = 'missing.cmxs'
  else if (kind === 'missing-bytecode') receipt.artifacts.bytecode.path = 'missing.cma'
  else fail(`unsupported fixture mutation: ${kind}`)
  fs.mkdirSync(path.dirname(outputPath), { recursive: true })
  fs.writeFileSync(outputPath, `${JSON.stringify(receipt, null, 2)}\n`)
  process.stdout.write(`${outputPath}\n`)
}

function main() {
  const { command, values } = parseArgs(process.argv)
  if (command === 'write') {
    writeReceipt(values)
    return
  }
  if (command === 'validate') {
    const reportPath = path.resolve(required(values, 'report'))
    const result = validateReceipt(reportPath, values.get('expected-candidate'))
    process.stdout.write(`${JSON.stringify({
      schema: result.receipt.schema,
      candidateCommit: result.receipt.candidateCommit,
      pluginId: result.receipt.pluginId,
      expressions: result.receipt.expressions,
      artifacts: {
        native: { path: result.native.artifactPath, sha256: result.native.actualDigest },
        bytecode: { path: result.bytecode.artifactPath, sha256: result.bytecode.actualDigest },
      },
    })}\n`)
    return
  }
  if (command === 'mutate-fixture') {
    mutateFixture(values)
    return
  }
  fail('expected command: write|validate|mutate-fixture')
}

main()
