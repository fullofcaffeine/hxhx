#!/usr/bin/env node
'use strict'

// Build the official formatter from pinned sources plus the reviewed lexer fix.
// Runtime callers accept only the recorded output digest, never an ambient tool.
const fs = require('fs')
const path = require('path')
const os = require('os')
const crypto = require('crypto')
const { spawnSync } = require('child_process')

const root = path.resolve(__dirname, '../..')
const lock = require('./formatter-toolchain.lock.json')
const patch = path.join(__dirname, 'formatter-lexer-scan.patch')
const artifact = path.join(root, '.tmp/formatter-toolchain', lock.artifactSha256, 'run.js')
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex')

/** Resolve only the exact reviewed formatter, with no fallback after damage. */
function formatterCommand() {
  if (!fs.existsSync(artifact) || digest(fs.readFileSync(artifact)) !== lock.artifactSha256) {
    throw new Error('Pinned formatter is missing or changed. Run node scripts/lint/formatter-toolchain.js --install')
  }
  return { command: process.execPath, args: [artifact] }
}

function run(command, args, cwd, env = process.env) {
  const result = spawnSync(command, args, { cwd, env, stdio: 'inherit', timeout: 180000 })
  if (result.error || result.signal || result.status !== 0) {
    throw new Error(`${path.basename(command)} failed: ${result.error?.message || result.signal || result.status}`)
  }
}

function checkout(destination, source) {
  fs.mkdirSync(destination)
  run('git', ['init', '--quiet'], destination)
  run('git', ['fetch', '--quiet', '--depth', '1', source.url, source.revision], destination)
  run('git', ['checkout', '--quiet', '--detach', 'FETCH_HEAD'], destination)
}

/** Expand only locked library HXML files while retaining every compiler option. */
function buildInputs(project, cache) {
  const visited = new Set()
  const libraries = new Set()
  function expand(file) {
    if (visited.has(file)) return []
    visited.add(file)
    return fs.readFileSync(file, 'utf8').split(/\r?\n/).flatMap(raw => {
      const line = raw.trim()
      if (!line || line.startsWith('#')) return []
      if (line.startsWith('-lib ')) {
        const name = line.slice(5)
        if (!/^[a-zA-Z0-9_.-]+$/.test(name)) throw new Error(`Unsupported locked library: ${name}`)
        libraries.add(`${name}.hxml`)
        return expand(path.join(project, 'haxe_libraries', `${name}.hxml`))
      }
      if (!line.startsWith('-') && line.endsWith('.hxml')) return expand(path.join(project, line))
      return [line.replaceAll('${HAXE_LIBCACHE}', cache)]
    })
  }
  return { lines: expand(path.join(project, 'buildJsNode.hxml')), libraries }
}

/** Build in a private directory; publish the artifact only after its digest matches. */
function install() {
  if (digest(fs.readFileSync(patch)) !== lock.patchSha256) throw new Error('Formatter patch does not match its lock')
  const lix = path.join(root, 'node_modules/lix/bin/lix.js')
  if (!fs.existsSync(lix)) throw new Error('Run npm ci before installing the formatter')
  const haxeRoot = process.env.HAXE_ROOT || process.env.HAXESHIM_ROOT || path.join(process.platform === 'win32' ? process.env.APPDATA : os.homedir(), 'haxe')
  const cache = process.env.HAXE_LIBCACHE || path.join(haxeRoot, 'haxe_libraries')
  const haxe = path.join(haxeRoot, 'versions', lock.haxe, process.platform === 'win32' ? 'haxe.exe' : 'haxe')
  if (!fs.existsSync(haxe)) throw new Error(`Install Haxe ${lock.haxe} with npx lix download haxe ${lock.haxe}`)
  const env = { ...process.env, HAXE_STD_PATH: path.join(path.dirname(haxe), 'std') }
  const version = spawnSync(haxe, ['--version'], { env, encoding: 'utf8', timeout: 10000 })
  if (version.status !== 0 || version.stdout.trim() !== lock.haxe) throw new Error('Unexpected Haxe compiler version')
  fs.mkdirSync(path.join(root, '.tmp'), { recursive: true })
  const scratch = fs.mkdtempSync(path.join(root, '.tmp/formatter-build-'))
  try {
    const project = path.join(scratch, 'formatter')
    const lexer = path.join(scratch, 'lexer')
    checkout(project, lock.formatter)
    checkout(lexer, lock.lexer)
    run('git', ['apply', '--unidiff-zero', patch], lexer)
    fs.writeFileSync(path.join(project, '.haxerc'), JSON.stringify({ version: lock.haxe, resolveLibs: 'scoped' }))
    const { lines, libraries } = buildInputs(project, cache)
    // The release also pins native/test dependencies that this JS build does not use.
    for (const name of fs.readdirSync(path.join(project, 'haxe_libraries'))) {
      if (!libraries.has(name)) fs.unlinkSync(path.join(project, 'haxe_libraries', name))
    }
    run(process.execPath, [lix, 'download'], project)
    lines.push(`-cp ${path.join(lexer, 'src')}`)
    const hxml = path.join(scratch, 'build.hxml')
    fs.writeFileSync(hxml, `${lines.join('\n')}\n`)
    run(haxe, [hxml], project, env)
    const output = fs.readFileSync(path.join(project, 'run.js'))
    if (digest(output) !== lock.artifactSha256) throw new Error('Formatter build output differs from the reviewed digest')
    fs.mkdirSync(path.dirname(artifact), { recursive: true })
    const staged = path.join(scratch, 'run.js')
    fs.writeFileSync(staged, output)
    fs.renameSync(staged, artifact)
    console.log(`FORMATTER_TOOLCHAIN:PASS sha256=${lock.artifactSha256}`)
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true })
  }
}

if (require.main === module) {
  try {
    if (process.argv.length === 3 && process.argv[2] === '--install') install()
    else if (process.argv[2] === '--run') {
      const formatter = formatterCommand()
      process.argv = [process.execPath, formatter.args[0], ...process.argv.slice(3)]
      require(formatter.args[0])
    } else throw new Error('Usage: node scripts/lint/formatter-toolchain.js --install | --run [formatter arguments]')
  } catch (error) {
    console.error(`[formatter-toolchain] ${error.message}`)
    process.exitCode = 1
  }
}

module.exports = { formatterCommand, buildInputs }
