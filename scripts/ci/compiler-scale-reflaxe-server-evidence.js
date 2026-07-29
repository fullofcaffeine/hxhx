#!/usr/bin/env node
/**
 * Builds and validates one compiler-scale cold/warm Reflaxe evidence report.
 *
 * The shell runner owns compiler, server, Dune, and cleanup orchestration. This
 * helper owns content hashing and report validation so shell code never has to
 * parse or construct nested JSON. A passing report means that the cold and warm
 * requests published the same complete target program, built the same binary,
 * behaved the same under `--version`, and saved material end-to-end time.
 */

'use strict'

const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const REPORT_SCHEMA = 'hxhx.compiler-scale-reflaxe-server.v1'
const CAPTURE_SCHEMA = 'hxhx.compiler-scale-reflaxe-capture.v1'

function fail(message) {
  throw new Error(message)
}

function readValue(argv, index, flag) {
  if (index + 1 >= argv.length) fail(`${flag} requires a value`)
  return argv[index + 1]
}

function parseFlags(argv) {
  const result = {}
  for (let index = 0; index < argv.length; index++) {
    const flag = argv[index]
    if (!flag.startsWith('--')) fail(`unexpected argument: ${flag}`)
    const key = flag.slice(2).replaceAll('-', '_')
    result[key] = readValue(argv, index, flag)
    index++
  }
  return result
}

function required(options, key) {
  const value = options[key]
  if (typeof value !== 'string' || value.length === 0) fail(`--${key.replaceAll('_', '-')} is required`)
  return value
}

function integer(options, key) {
  const raw = required(options, key)
  const value = Number(raw)
  if (!Number.isInteger(value) || value < 0) fail(`--${key.replaceAll('_', '-')} must be a non-negative integer`)
  return value
}

function boolean(options, key) {
  const raw = required(options, key)
  if (raw === 'true') return true
  if (raw === 'false') return false
  fail(`--${key.replaceAll('_', '-')} must be true or false`)
}

function readJson(file, label = file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch (error) {
    fail(`could not read ${label}: ${error.message}`)
  }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`)
}

function sha256Bytes(bytes) {
  return `sha256:${crypto.createHash('sha256').update(bytes).digest('hex')}`
}

function sha256File(file) {
  return sha256Bytes(fs.readFileSync(file))
}

function sha256Tree(root) {
  const hash = crypto.createHash('sha256')
  let fileCount = 0
  let byteCount = 0
  const visit = (directory, prefix) => {
    const entries = fs.readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name < right.name ? -1 : (left.name > right.name ? 1 : 0))
    for (const entry of entries) {
      const relative = prefix === '' ? entry.name : `${prefix}/${entry.name}`
      const absolute = path.join(directory, entry.name)
      if (entry.isDirectory()) {
        visit(absolute, relative)
      } else if (entry.isFile()) {
        const bytes = fs.readFileSync(absolute)
        hash.update(Buffer.from(relative, 'utf8'))
        hash.update(Buffer.from([0]))
        hash.update(bytes)
        hash.update(Buffer.from([0]))
        fileCount++
        byteCount += bytes.length
      } else {
        fail(`unsupported generated-tree entry: ${absolute}`)
      }
    }
  }
  visit(root, '')
  return {
    revision: `sha256:${hash.digest('hex')}`,
    file_count: fileCount,
    byte_count: byteCount
  }
}

function normalizeText(file) {
  return fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n')
}

function capture(options) {
  const outputDir = path.resolve(required(options, 'output_dir'))
  const executable = path.resolve(required(options, 'executable'))
  const versionStdout = path.resolve(required(options, 'version_stdout'))
  const versionStderr = path.resolve(required(options, 'version_stderr'))
  const out = path.resolve(required(options, 'out'))
  const manifestPath = path.join(outputDir, 'ocaml_artifact_manifest.json')
  const generatedPath = path.join(outputDir, '_GeneratedFiles.json')
  for (const file of [manifestPath, generatedPath, executable, versionStdout, versionStderr]) {
    if (!fs.existsSync(file)) fail(`required evidence file is missing: ${file}`)
  }
  const manifest = readJson(manifestPath, 'OCaml artifact manifest')
  const generated = readJson(generatedPath, 'generated-file receipt')
  if (typeof manifest.programRevision !== 'string' || !manifest.programRevision.startsWith('sha256:')) {
    fail('OCaml artifact manifest has no programRevision')
  }
  if (typeof manifest.summary?.sourceBundleRevision !== 'string'
      || !manifest.summary.sourceBundleRevision.startsWith('sha256:')) {
    fail('OCaml artifact manifest has no summary.sourceBundleRevision')
  }
  if (!Array.isArray(generated.filesGenerated) || generated.filesGenerated.length === 0) {
    fail('generated-file receipt has no filesGenerated entries')
  }
  const tree = sha256Tree(outputDir)
  const record = {
    schema: CAPTURE_SCHEMA,
    generated_tree: tree,
    program_revision: manifest.programRevision,
    source_bundle_revision: manifest.summary.sourceBundleRevision,
    artifact_manifest_sha256: sha256File(manifestPath),
    generated_files_sha256: sha256File(generatedPath),
    generated_file_receipt_count: generated.filesGenerated.length,
    executable_sha256: sha256File(executable),
    version_behavior: {
      exit_code: integer(options, 'version_exit'),
      stdout: normalizeText(versionStdout),
      stdout_sha256: sha256File(versionStdout),
      stderr: normalizeText(versionStderr),
      stderr_sha256: sha256File(versionStderr)
    }
  }
  writeJson(out, record)
  process.stdout.write(`${out}\n`)
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

function validateCapture(record, label, errors) {
  if (!record || record.schema !== CAPTURE_SCHEMA) {
    errors.push(`${label}.schema is invalid`)
    return
  }
  for (const key of [
    'program_revision',
    'source_bundle_revision',
    'artifact_manifest_sha256',
    'generated_files_sha256',
    'executable_sha256'
  ]) {
    if (typeof record[key] !== 'string' || !record[key].startsWith('sha256:')) {
      errors.push(`${label}.${key} is not a sha256 revision`)
    }
  }
  if (typeof record.generated_tree?.revision !== 'string'
      || !record.generated_tree.revision.startsWith('sha256:')) {
    errors.push(`${label}.generated_tree.revision is invalid`)
  }
  for (const key of ['file_count', 'byte_count']) {
    if (!Number.isInteger(record.generated_tree?.[key]) || record.generated_tree[key] < 1) {
      errors.push(`${label}.generated_tree.${key} is invalid`)
    }
  }
  if (!Number.isInteger(record.generated_file_receipt_count)
      || record.generated_file_receipt_count < 1) {
    errors.push(`${label}.generated_file_receipt_count is invalid`)
  }
  if (!Number.isInteger(record.version_behavior?.exit_code)
      || record.version_behavior.exit_code !== 0) {
    errors.push(`${label}.version_behavior.exit_code must be zero`)
  }
  for (const key of ['stdout_sha256', 'stderr_sha256']) {
    if (typeof record.version_behavior?.[key] !== 'string'
        || !record.version_behavior[key].startsWith('sha256:')) {
      errors.push(`${label}.version_behavior.${key} is invalid`)
    }
  }
}

function validateReport(report) {
  const errors = []
  if (!report || report.schema !== REPORT_SCHEMA) errors.push('schema is invalid')
  if (report.evidence_level !== 'checkpoint') errors.push('evidence_level must be checkpoint')
  if (report.environment?.haxe_version !== '4.3.7') errors.push('environment.haxe_version must be 4.3.7')
  if (report.capacity?.status !== 'pass') errors.push('capacity.status must be pass')
  if (report.source?.clean_at_start !== true || report.source?.clean_at_end !== true) {
    errors.push('source must be clean at start and end')
  }
  validateCapture(report.cold?.capture, 'cold.capture', errors)
  validateCapture(report.warm?.capture, 'warm.capture', errors)
  for (const owner of ['cold', 'warm']) {
    for (const key of ['generation_ms', 'dune_ms', 'full_ms']) {
      if (!Number.isInteger(report[owner]?.timing?.[key]) || report[owner].timing[key] < 0) {
        errors.push(`${owner}.timing.${key} is invalid`)
      }
    }
    if (report[owner]?.timing?.full_ms
        !== report[owner]?.timing?.generation_ms + report[owner]?.timing?.dune_ms) {
      errors.push(`${owner}.timing.full_ms does not equal generation_ms + dune_ms`)
    }
  }
  const coldCapture = report.cold?.capture
  const warmCapture = report.warm?.capture
  for (const key of [
    'program_revision',
    'source_bundle_revision',
    'artifact_manifest_sha256',
    'generated_files_sha256',
    'generated_file_receipt_count',
    'executable_sha256'
  ]) {
    if (coldCapture?.[key] !== warmCapture?.[key]) errors.push(`cold/warm ${key} differs`)
  }
  if (!sameJson(coldCapture?.generated_tree, warmCapture?.generated_tree)) {
    errors.push('cold/warm generated_tree differs')
  }
  if (!sameJson(coldCapture?.version_behavior, warmCapture?.version_behavior)) {
    errors.push('cold/warm version behavior differs')
  }
  if (report.performance?.cold_full_ms !== report.cold?.timing?.full_ms
      || report.performance?.warm_full_ms !== report.warm?.timing?.full_ms) {
    errors.push('performance totals do not match phase timings')
  }
  const savedMs = report.cold?.timing?.full_ms - report.warm?.timing?.full_ms
  if (!Number.isInteger(report.performance?.minimum_absolute_saved_ms)
      || report.performance.minimum_absolute_saved_ms < 0) {
    errors.push('performance.minimum_absolute_saved_ms is invalid')
  }
  if (!Number.isFinite(report.performance?.maximum_warm_to_cold_ratio)
      || report.performance.maximum_warm_to_cold_ratio <= 0
      || report.performance.maximum_warm_to_cold_ratio >= 1) {
    errors.push('performance.maximum_warm_to_cold_ratio is invalid')
  }
  const ratio = report.cold?.timing?.full_ms > 0
    ? report.warm.timing.full_ms / report.cold.timing.full_ms
    : 1
  const material = savedMs >= report.performance?.minimum_absolute_saved_ms
    || ratio <= report.performance?.maximum_warm_to_cold_ratio
  if (report.performance?.saved_ms !== savedMs) errors.push('performance.saved_ms is incorrect')
  if (report.performance?.material_benefit !== material) {
    errors.push('performance.material_benefit is incorrect')
  }
  if (!material) errors.push('warm full loop did not demonstrate a material benefit')
  for (const key of ['baseline_kb', 'after_cold_kb', 'after_warm_kb', 'peak_kb', 'final_kb']) {
    if (!Number.isInteger(report.server_memory?.[key]) || report.server_memory[key] < 0) {
      errors.push(`server_memory.${key} is invalid`)
    }
  }
  if (report.server_memory?.peak_kb < Math.max(
    report.server_memory?.baseline_kb || 0,
    report.server_memory?.after_cold_kb || 0,
    report.server_memory?.after_warm_kb || 0,
    report.server_memory?.final_kb || 0
  )) {
    errors.push('server_memory.peak_kb is below an observed sample')
  }
  if (report.cleanup?.owned_pids_after_stop !== 0) errors.push('owned server PIDs remained after stop')
  if (report.cleanup?.private_candidates_after_stop !== 0) errors.push('private output candidates remained')
  if (report.cleanup?.pid_state_after_stop !== 0) errors.push('server PID state remained after stop')
  if (report.status !== (errors.length === 0 ? 'pass' : 'fail')) {
    errors.push(`status is ${JSON.stringify(report.status)} but validation found ${errors.length} error(s)`)
  }
  return errors
}

function report(options) {
  const coldCapture = readJson(path.resolve(required(options, 'cold_capture')), 'cold capture')
  const warmCapture = readJson(path.resolve(required(options, 'warm_capture')), 'warm capture')
  const capacity = readJson(path.resolve(required(options, 'capacity_report')), 'capacity report')
  const coldGenerationMs = integer(options, 'cold_generation_ms')
  const coldDuneMs = integer(options, 'cold_dune_ms')
  const warmGenerationMs = integer(options, 'warm_generation_ms')
  const warmDuneMs = integer(options, 'warm_dune_ms')
  const minimumAbsoluteSavedMs = integer(options, 'minimum_absolute_saved_ms')
  const maximumWarmToColdRatio = Number(required(options, 'maximum_warm_to_cold_ratio'))
  if (!Number.isFinite(maximumWarmToColdRatio)
      || maximumWarmToColdRatio <= 0
      || maximumWarmToColdRatio >= 1) {
    fail('--maximum-warm-to-cold-ratio must be greater than zero and less than one')
  }
  const coldFullMs = coldGenerationMs + coldDuneMs
  const warmFullMs = warmGenerationMs + warmDuneMs
  const savedMs = coldFullMs - warmFullMs
  const materialBenefit = savedMs >= minimumAbsoluteSavedMs
    || (coldFullMs > 0 && warmFullMs / coldFullMs <= maximumWarmToColdRatio)
  const result = {
    schema: REPORT_SCHEMA,
    evidence_level: 'checkpoint',
    status: 'pending',
    generated_at: new Date().toISOString(),
    source: {
      commit: required(options, 'source_commit'),
      clean_at_start: boolean(options, 'source_clean_at_start'),
      clean_at_end: boolean(options, 'source_clean_at_end')
    },
    environment: {
      platform: os.platform(),
      release: os.release(),
      architecture: os.arch(),
      cpu_count: os.cpus().length,
      haxe_bin: required(options, 'haxe_bin'),
      haxe_version: required(options, 'haxe_version'),
      ocamlopt_version: required(options, 'ocamlopt_version'),
      dune_version: required(options, 'dune_version')
    },
    ceiling: {
      generation_seconds: integer(options, 'generation_ceiling_seconds'),
      dune_seconds: integer(options, 'dune_ceiling_seconds'),
      rationale: required(options, 'ceiling_rationale')
    },
    capacity,
    cold: {
      timing: {
        generation_ms: coldGenerationMs,
        dune_ms: coldDuneMs,
        full_ms: coldFullMs
      },
      capture: coldCapture
    },
    warm: {
      timing: {
        generation_ms: warmGenerationMs,
        dune_ms: warmDuneMs,
        full_ms: warmFullMs
      },
      capture: warmCapture
    },
    performance: {
      cold_full_ms: coldFullMs,
      warm_full_ms: warmFullMs,
      saved_ms: savedMs,
      speedup: warmFullMs > 0 ? Number((coldFullMs / warmFullMs).toFixed(3)) : null,
      minimum_absolute_saved_ms: minimumAbsoluteSavedMs,
      maximum_warm_to_cold_ratio: maximumWarmToColdRatio,
      material_benefit: materialBenefit
    },
    server_memory: {
      baseline_kb: integer(options, 'rss_baseline_kb'),
      after_cold_kb: integer(options, 'rss_after_cold_kb'),
      after_warm_kb: integer(options, 'rss_after_warm_kb'),
      peak_kb: integer(options, 'rss_peak_kb'),
      final_kb: integer(options, 'rss_final_kb')
    },
    cleanup: {
      owned_pids_after_stop: integer(options, 'owned_pids_after_stop'),
      private_candidates_after_stop: integer(options, 'private_candidates_after_stop'),
      pid_state_after_stop: integer(options, 'pid_state_after_stop')
    }
  }
  result.status = validateReport({ ...result, status: 'pass' }).length === 0 ? 'pass' : 'fail'
  const out = path.resolve(required(options, 'out'))
  writeJson(out, result)
  const errors = validateReport(result)
  if (errors.length > 0) {
    for (const error of errors) console.error(`compiler-scale server evidence: ${error}`)
    process.exitCode = 1
  } else {
    console.log(`COMPILER_SCALE_REFLAXE_SERVER:PASS report=${out}`)
  }
}

function validate(options) {
  const file = path.resolve(required(options, 'report'))
  const errors = validateReport(readJson(file, 'compiler-scale server report'))
  if (errors.length > 0) {
    for (const error of errors) console.error(`compiler-scale server evidence: ${error}`)
    process.exitCode = 1
    return
  }
  console.log(`COMPILER_SCALE_REFLAXE_SERVER_REPORT:PASS report=${file}`)
}

function usage() {
  console.log(`Usage:
  node scripts/ci/compiler-scale-reflaxe-server-evidence.js capture [flags]
  node scripts/ci/compiler-scale-reflaxe-server-evidence.js report [flags]
  node scripts/ci/compiler-scale-reflaxe-server-evidence.js validate --report <file>`)
}

const [command, ...argv] = process.argv.slice(2)
try {
  const options = parseFlags(argv)
  if (command === 'capture') capture(options)
  else if (command === 'report') report(options)
  else if (command === 'validate') validate(options)
  else if (command === '-h' || command === '--help' || !command) usage()
  else fail(`unknown command: ${command}`)
} catch (error) {
  console.error(`compiler-scale server evidence: ${error.message}`)
  process.exitCode = 1
}
