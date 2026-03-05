#!/usr/bin/env node
/**
 * run-upstream-suite.js
 *
 * Full1 upstream suite runner with deterministic artifacts.
 * Runs one suite at a time in strict mode by default and emits suite markers on success.
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const SUITES = {
  misc: {
    marker: 'FULL1_SUITE_MISC:PASS',
    cwd: 'vendor/haxe/tests/misc',
    entryHxml: 'compile.hxml',
  },
  server: {
    marker: 'FULL1_SUITE_SERVER:PASS',
    cwd: 'vendor/haxe/tests/server',
    entryHxml: 'run.hxml',
  },
  threads: {
    marker: 'FULL1_SUITE_THREADS:PASS',
    cwd: 'vendor/haxe/tests/threads',
    entryHxml: 'build.hxml',
  },
  optimization: {
    marker: 'FULL1_SUITE_OPTIMIZATION:PASS',
    cwd: 'vendor/haxe/tests/optimization',
    entryHxml: 'run.hxml',
  },
  display: {
    marker: 'FULL1_SUITE_DISPLAY:PASS',
    cwd: 'vendor/haxe/tests/display',
    entryHxml: 'build.hxml',
  },
}

function fail(message) {
  console.error(`[full1-suite] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const out = {
    suite: '',
    strict: true,
    root: process.cwd(),
    upstreamDir: '',
    artifactsDir: '.artifacts/full1/suites',
    hxhxBin: process.env.HXHX_BIN || '',
    miscFilter: process.env.MISC_TEST_FILTER || '',
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--suite') {
      out.suite = String(argv[i + 1] || '').trim().toLowerCase()
      i += 1
      continue
    }
    if (arg === '--strict') {
      out.strict = true
      continue
    }
    if (arg === '--no-strict') {
      out.strict = false
      continue
    }
    if (arg === '--root') {
      out.root = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--upstream-dir') {
      out.upstreamDir = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--artifacts-dir') {
      out.artifactsDir = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--hxhx-bin') {
      out.hxhxBin = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--misc-filter') {
      out.miscFilter = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    fail(`unknown argument: ${arg}`)
  }

  if (!out.suite) {
    fail('missing required argument --suite <misc|server|threads|optimization|display>')
  }
  if (!(out.suite in SUITES)) {
    fail(`unsupported suite "${out.suite}"`)
  }
  if (!out.upstreamDir) {
    out.upstreamDir = path.join(out.root, 'vendor/haxe')
  }
  if (!fs.existsSync(out.upstreamDir)) {
    fail(`upstream checkout not found: ${out.upstreamDir}`)
  }
  if (!fs.existsSync(path.join(out.upstreamDir, 'tests'))) {
    fail(`upstream tests directory missing under: ${out.upstreamDir}`)
  }

  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function runCommand(command, args, options) {
  return cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64,
  })
}

function parseHxmlDirective(line) {
  const trimmed = line.trim()
  if (!trimmed || trimmed.startsWith('#')) {
    return null
  }

  const firstWhitespace = trimmed.search(/\s/)
  if (firstWhitespace < 0) {
    return { key: trimmed, value: '' }
  }

  return {
    key: trimmed.slice(0, firstWhitespace),
    value: trimmed.slice(firstWhitespace + 1).trim(),
  }
}

function parseHxmlCommandGroups(hxmlPath) {
  if (!fs.existsSync(hxmlPath)) {
    fail(`suite hxml not found: ${hxmlPath}`)
  }

  const directives = readUtf8(hxmlPath)
    .split(/\r?\n/)
    .map((line) => parseHxmlDirective(line))
    .filter((directive) => directive !== null)

  let sharedEach = []
  let groups = [[]]
  for (const directive of directives) {
    if (directive.key === '--each') {
      sharedEach = groups[0].slice()
      groups = [[]]
      continue
    }
    if (directive.key === '--next') {
      groups.push([])
      continue
    }
    groups[groups.length - 1].push(directive)
  }

  const nonEmptyGroups = groups.filter((group) => group.length > 0)
  if (sharedEach.length === 0) {
    return nonEmptyGroups
  }
  return nonEmptyGroups.map((group) => [...sharedEach, ...group])
}

function directiveGroupToArgv(group) {
  const out = []
  for (const directive of group) {
    out.push(directive.key)
    if (directive.value) {
      out.push(directive.value)
    }
  }
  return out
}

function isShellOnlyCommand(args) {
  return args.length === 2 && (args[0] === '-cmd' || args[0] === '--cmd')
}

function hasMiscFilterDefine(args) {
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] !== '-D') {
      continue
    }
    const value = String(args[i + 1] || '')
    if (value.startsWith('MISC_TEST_FILTER=')) {
      return true
    }
  }
  return false
}

function resolveHxhxBinary(root, currentValue) {
  if (currentValue) {
    const resolved = path.resolve(root, currentValue)
    if (fs.existsSync(resolved)) {
      return resolved
    }
    fail(`provided --hxhx-bin does not exist: ${resolved}`)
  }

  const buildScript = path.join(root, 'scripts/hxhx/build-hxhx.sh')
  const buildResult = runCommand('bash', [buildScript], {
    cwd: root,
    env: process.env,
  })
  const stdoutText = buildResult.stdout || ''
  const stderrText = buildResult.stderr || ''
  const buildText = `${stdoutText}${stderrText}`
  if (buildResult.status !== 0) {
    fail(`failed to build hxhx binary (exit ${buildResult.status})\n${buildText}`)
  }

  // build-hxhx.sh prints the binary path on stdout; stderr may include progress heartbeats.
  // Parse only stdout candidates so heartbeat/status lines can never be misread as a path.
  const stdoutLines = stdoutText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)

  const candidate = stdoutLines.length > 0 ? stdoutLines[stdoutLines.length - 1] : ''
  if (!candidate || candidate.startsWith('== ')) {
    fail('build-hxhx.sh did not print output binary path')
  }

  const resolved = path.resolve(root, candidate)
  if (!fs.existsSync(resolved)) {
    fail(`built hxhx binary path does not exist: ${resolved}`)
  }
  return resolved
}

function buildSuiteCommands(parsed, suiteConfig, suiteDir) {
  const entryHxmlPath = path.join(suiteDir, suiteConfig.entryHxml)
  const groups = parseHxmlCommandGroups(entryHxmlPath)
  const commands = []

  for (const group of groups) {
    const args = directiveGroupToArgv(group)
    if (parsed.suite === 'misc' && parsed.miscFilter && !hasMiscFilterDefine(args)) {
      args.push('-D', `MISC_TEST_FILTER=${parsed.miscFilter}`)
    }
    if (isShellOnlyCommand(args)) {
      commands.push({
        kind: 'shell',
        argv: ['bash', '-lc', args[1]],
        display: args[1],
      })
      continue
    }
    commands.push({
      kind: 'hxhx',
      argv: args,
      display: [parsed.hxhxBin || '<built-hxhx>', ...args].join(' '),
    })
  }

  if (commands.length === 0) {
    fail(`suite entrypoint produced no runnable commands: ${entryHxmlPath}`)
  }

  return commands
}

function main() {
  const parsed = parseArgs(process.argv.slice(2))
  const suiteConfig = SUITES[parsed.suite]
  const suiteDir = path.join(parsed.root, suiteConfig.cwd)
  if (!fs.existsSync(suiteDir)) {
    fail(`suite directory not found: ${suiteDir}`)
  }

  ensureDir(parsed.artifactsDir)
  const logPath = path.join(parsed.artifactsDir, `${parsed.suite}.log`)
  const summaryPath = path.join(parsed.artifactsDir, `${parsed.suite}.summary.json`)

  const hxhxBin = resolveHxhxBinary(parsed.root, parsed.hxhxBin)
  const suiteCommands = buildSuiteCommands(parsed, suiteConfig, suiteDir)
  for (const command of suiteCommands) {
    if (command.kind === 'hxhx') {
      command.display = [hxhxBin, ...command.argv].join(' ')
    }
  }
  const env = { ...process.env }
  if (parsed.strict) {
    env.HXHX_FORBID_STAGE0 = '1'
  }

  const startedAt = new Date()
  const commandRuns = []
  let failedCommandIndex = -1
  let suiteExitCode = 0

  for (let i = 0; i < suiteCommands.length; i += 1) {
    const command = suiteCommands[i]
    const commandStartedAt = new Date()
    const result = command.kind === 'shell'
      ? runCommand(command.argv[0], command.argv.slice(1), { cwd: suiteDir, env })
      : runCommand(hxhxBin, command.argv, { cwd: suiteDir, env })
    const commandEndedAt = new Date()
    const commandExit = result.status == null ? -1 : result.status

    commandRuns.push({
      index: i,
      kind: command.kind,
      display: command.display,
      argv: command.kind === 'shell' ? command.argv.slice() : [hxhxBin, ...command.argv],
      startedAt: commandStartedAt,
      endedAt: commandEndedAt,
      durationMs: commandEndedAt.getTime() - commandStartedAt.getTime(),
      exitCode: commandExit,
      signal: result.signal || '',
      stdout: result.stdout || '',
      stderr: result.stderr || '',
      error: result.error ? String(result.error.message || result.error) : '',
    })

    if (result.error) {
      failedCommandIndex = i
      suiteExitCode = 1
      break
    }
    if (commandExit !== 0) {
      failedCommandIndex = i
      suiteExitCode = commandExit || 1
      break
    }
  }

  const endedAt = new Date()
  const durationMs = endedAt.getTime() - startedAt.getTime()
  const combinedLog = [
    `suite=${parsed.suite}`,
    `strict=${parsed.strict ? '1' : '0'}`,
    `cwd=${suiteDir}`,
    `hxhx_bin=${hxhxBin}`,
    `commands_total=${suiteCommands.length}`,
    `failed_command_index=${failedCommandIndex}`,
    `started_at=${startedAt.toISOString()}`,
    `ended_at=${endedAt.toISOString()}`,
    `duration_ms=${durationMs}`,
  ].join('\n')
  const commandLogs = []
  for (const run of commandRuns) {
    commandLogs.push(
      [
        '',
        `--- command[${run.index}] ---`,
        `kind=${run.kind}`,
        `display=${run.display}`,
        `exit_code=${run.exitCode}`,
        `signal=${run.signal}`,
        `started_at=${run.startedAt.toISOString()}`,
        `ended_at=${run.endedAt.toISOString()}`,
        `duration_ms=${run.durationMs}`,
        run.error ? `error=${run.error}` : '',
        '',
        'stdout:',
        run.stdout,
        'stderr:',
        run.stderr,
      ]
        .filter((line) => line !== '')
        .join('\n'),
    )
  }
  fs.writeFileSync(logPath, `${combinedLog}\n${commandLogs.join('\n')}\n`, 'utf8')

  const summary = {
    schema: 'full1-upstream-suite-summary.v1',
    suite: parsed.suite,
    strict: parsed.strict,
    marker: suiteConfig.marker,
    commands: commandRuns.map((run) => ({
      index: run.index,
      kind: run.kind,
      argv: run.argv,
      display: run.display,
      started_at: run.startedAt.toISOString(),
      ended_at: run.endedAt.toISOString(),
      duration_ms: run.durationMs,
      exit_code: run.exitCode,
      signal: run.signal,
      error: run.error,
    })),
    failed_command_index: failedCommandIndex,
    cwd: suiteDir,
    hxhx_bin: hxhxBin,
    artifacts: {
      log: logPath,
    },
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: durationMs,
    exit_code: suiteExitCode,
    signal: '',
  }
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8')

  if (suiteExitCode !== 0) {
    console.error(`[full1-suite] suite=${parsed.suite} failed (exit ${suiteExitCode}). log=${logPath}`)
    process.exit(suiteExitCode)
  }

  console.log(`[full1-suite] suite=${parsed.suite} succeeded. log=${logPath}`)
  console.log(`[full1-suite] summary=${summaryPath}`)
  console.log(suiteConfig.marker)
}

main()
