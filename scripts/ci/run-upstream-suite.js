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

const SUITE_HAXELIB_DEPS = {
  server: [
    { name: 'utest', repo: 'https://github.com/haxe-utest/utest', ref: 'a94f8812e8786f2b5fec52ce9f26927591d26327' },
    { name: 'haxeserver', repo: 'https://github.com/Simn/haxeserver' },
    { name: 'hxnodejs', repo: 'https://github.com/HaxeFoundation/hxnodejs' },
  ],
  display: [
    { name: 'utest', repo: 'https://github.com/haxe-utest/utest', ref: 'a94f8812e8786f2b5fec52ce9f26927591d26327' },
    { name: 'haxeserver', repo: 'https://github.com/Simn/haxeserver' },
  ],
  threads: [
    { name: 'utest', repo: 'https://github.com/haxe-utest/utest', ref: 'a94f8812e8786f2b5fec52ce9f26927591d26327' },
  ],
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

function resolveHaxelibBin() {
  const configured = String(process.env.HAXELIB_BIN || '').trim()
  return configured || 'haxelib'
}

function parseHaxelibPathLines(outputText) {
  const lines = String(outputText || '').split(/\r?\n/)
  const parsed = []
  for (const rawLine of lines) {
    const line = rawLine.trim()
    if (!line) {
      continue
    }
    parsed.push(line)
  }
  return parsed
}

function probeHaxelibPathLines(haxelibBin, lib, cwd, env) {
  const probe = runCommand(haxelibBin, ['--always', 'path', lib], { cwd, env })
  if (probe.status !== 0) {
    return null
  }
  const lines = parseHaxelibPathLines(probe.stdout || '')
  if (lines.length === 0) {
    return null
  }
  if (lines.some((line) => /^-lib\s+\S+\s+is missing\b/.test(line))) {
    return null
  }

  const classPaths = lines.filter((line) => !line.startsWith('-'))
  if (classPaths.length > 0 && classPaths.some((cpPath) => !fs.existsSync(cpPath))) {
    return null
  }
  return lines
}

function writeSuiteHaxelibHxml(lib, lines, suiteDir) {
  const hxmlDir = path.join(suiteDir, 'haxe_libraries')
  ensureDir(hxmlDir)
  const hxmlPath = path.join(hxmlDir, `${lib}.hxml`)
  const out = []
  for (const line of lines) {
    if (
      line.startsWith('-D ')
      || line.startsWith('--macro ')
      || line.startsWith('-cp ')
      || line.startsWith('--class-path ')
      || line.startsWith('-')
    ) {
      out.push(line)
      continue
    }
    out.push(`-cp ${line}`)
  }
  if (out.length === 0) {
    fail(`failed to generate haxelib hxml for ${lib}: no path/macros/defines emitted`)
  }
  fs.writeFileSync(hxmlPath, `${out.join('\n')}\n`, 'utf8')
}

function ensureSuiteDependencies(suite, cwd, env) {
  const deps = SUITE_HAXELIB_DEPS[suite] || []
  if (deps.length === 0) {
    return
  }

  const haxelibBin = resolveHaxelibBin()
  for (const dep of deps) {
    let resolvedLines = probeHaxelibPathLines(haxelibBin, dep.name, cwd, env)
    if (resolvedLines == null) {
      const installArgs = ['--always', 'git', dep.name, dep.repo]
      if (dep.ref) {
        installArgs.push(dep.ref)
      }

      let installOk = false
      let lastInstall = null
      for (let attempt = 1; attempt <= 3; attempt += 1) {
        const result = runCommand(haxelibBin, installArgs, { cwd, env })
        lastInstall = result
        resolvedLines = probeHaxelibPathLines(haxelibBin, dep.name, cwd, env)
        if (result.status === 0 && resolvedLines != null) {
          installOk = true
          break
        }
        const retryMessage = result.stderr || result.stdout || `exit=${result.status}`
        console.error(`[full1-suite] dependency install retry ${attempt}/3 for ${dep.name}: ${retryMessage}`)
      }

      if (!installOk || resolvedLines == null) {
        const errText = `${lastInstall && lastInstall.stdout ? lastInstall.stdout : ''}${lastInstall && lastInstall.stderr ? lastInstall.stderr : ''}`
        fail(`failed to install required dependency ${dep.name} via haxelib git\n${errText}`)
      }
    }

    writeSuiteHaxelibHxml(dep.name, resolvedLines, cwd)
  }
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

function hasExplicitTargetArg(args) {
  const targetFlags = new Set([
    '--ocaml',
    '--ocaml-eval',
    '--compat',
    '--js',
    '-js',
    '--lua',
    '--swf',
    '--neko',
    '--php',
    '--cpp',
    '--cppia',
    '--cs',
    '--java',
    '--jvm',
    '--python',
    '--hl',
    '--interp',
  ])
  return args.some((arg) => targetFlags.has(arg))
}

function normalizeNativeCommandArgs(args) {
  const out = []
  let sawInterp = false
  for (const arg of args) {
    if (arg === '--interp') {
      sawInterp = true
      continue
    }
    out.push(arg)
  }

  const hadTarget = hasExplicitTargetArg(out)
  if (!hadTarget) {
    out.unshift('--ocaml')
  }
  if ((sawInterp || !hadTarget) && !out.includes('--hxhx-no-emit')) {
    out.push('--hxhx-no-emit')
  }

  return out
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

function resolveMacroHostBinary(root, env) {
  const configured = String(env.HXHX_MACRO_HOST_EXE || '').trim()
  if (configured) {
    const resolvedConfigured = path.resolve(root, configured)
    if (!fs.existsSync(resolvedConfigured)) {
      fail(`provided HXHX_MACRO_HOST_EXE does not exist: ${resolvedConfigured}`)
    }
    return resolvedConfigured
  }

  const buildScript = path.join(root, 'scripts/hxhx/build-hxhx-macro-host.sh')
  const buildResult = runCommand('bash', [buildScript], {
    cwd: root,
    env,
  })
  const stdoutText = buildResult.stdout || ''
  const stderrText = buildResult.stderr || ''
  const buildText = `${stdoutText}${stderrText}`
  if (buildResult.status !== 0) {
    fail(`failed to build macro host binary (exit ${buildResult.status})\n${buildText}`)
  }

  const stdoutLines = stdoutText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)

  const candidate = stdoutLines.length > 0 ? stdoutLines[stdoutLines.length - 1] : ''
  if (!candidate || candidate.startsWith('== ')) {
    fail('build-hxhx-macro-host.sh did not print output binary path')
  }

  const resolved = path.resolve(root, candidate)
  if (!fs.existsSync(resolved)) {
    fail(`built macro host binary path does not exist: ${resolved}`)
  }
  return resolved
}

function normalizeMacroRuntimeMode(env) {
  const raw = String(env.HXHX_MACRO_RUNTIME_MODE || '').trim().toLowerCase()
  if (!raw) {
    return 'inproc'
  }
  return raw
}

function shouldResolveMacroHost(env) {
  const configured = String(env.HXHX_MACRO_HOST_EXE || '').trim()
  if (configured) {
    return true
  }
  return normalizeMacroRuntimeMode(env) === 'external-host'
}

function buildSuiteCommands(parsed, suiteConfig, suiteDir) {
  const entryHxmlPath = path.join(suiteDir, suiteConfig.entryHxml)
  const groups = parseHxmlCommandGroups(entryHxmlPath)
  const commands = []

  for (const group of groups) {
    const rawArgs = directiveGroupToArgv(group)
    const containsHxmlArg = rawArgs.some((arg) => arg.toLowerCase().endsWith('.hxml'))
    const args = containsHxmlArg ? rawArgs.slice() : normalizeNativeCommandArgs(rawArgs)
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
  if (!String(env.HXHX_MACRO_RUNTIME_MODE || '').trim()) {
    env.HXHX_MACRO_RUNTIME_MODE = 'inproc'
  }
  ensureSuiteDependencies(parsed.suite, suiteDir, env)
  if (shouldResolveMacroHost(env)) {
    env.HXHX_MACRO_HOST_EXE = resolveMacroHostBinary(parsed.root, env)
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
