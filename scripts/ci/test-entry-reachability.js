#!/usr/bin/env node
/**
 * Finds test entry points that no CI path can run.
 *
 * A test that CI never runs can rot silently: it keeps passing review because
 * nobody executes it, and the next person who runs it finds an old failure.
 * This guard lists every test entry point in the repository and walks the
 * references that CI starts from. An entry point is "reachable" when one of
 * these roots names it, directly or through other scripts and files:
 *
 * - each command of the `npm test` aggregate (the Core Tests shards run
 *   exactly these, see scripts/ci/core-test-shards.json);
 * - each npm script, script file, or `.hxml` file named in a
 *   `.github/workflows/*.yml` file.
 *
 * Entry points are top-level `test/*.hxml` files, `test:*` npm scripts,
 * `scripts/ci/*-test.js` files, and portable fixture directories under
 * `test/portable/fixtures`. Portable fixtures are discovered by directory, so
 * a fixture directory is reachable when `test:portable` is reachable and the
 * directory has the `build.hxml` file that the runner requires.
 *
 * References are found by text: `npm run <name>`, quoted npm script names,
 * repository paths such as `test/foo.hxml` or `scripts/ci/foo.js`, bare file
 * names that resolve beside the referring file, and the `test/<Main>.hx`
 * class that an `.hxml` file runs (a test can start other test builds).
 *
 * A wrapper npm script that nothing names, such as `test:x` = `node
 * scripts/ci/x.js` while a workflow calls that file directly, counts as
 * reachable only when CI runs each of its `&&` commands as written. A copy
 * with an extra environment variable, define, or argument is a variant that
 * CI never runs, so it stays unreachable.
 *
 * Entries that are unreachable on purpose are listed in
 * scripts/ci/test-entry-reachability.json with a reason and an owning Bead.
 * Files that only a listed entry runs share its exception; scripts never do,
 * so every unreachable npm script has its own entry.
 * The guard fails when a new unreachable entry is not listed, when a listed
 * entry has become reachable, when a listed entry no longer exists, or when an
 * npm script runs a `test/` or `scripts/` file that does not exist.
 */

const fs = require('fs')
const path = require('path')

const SCHEMA = 'hxhx.test-entry-reachability.v1'
const EXCEPTIONS_PATH = 'scripts/ci/test-entry-reachability.json'
const PORTABLE_ROOT = 'test/portable/fixtures'
const PORTABLE_COMMAND = 'test:portable'
const TEXT_EXTENSIONS = new Set(['.js', '.cjs', '.mjs', '.sh', '.hxml', '.hx', '.json', '.py', '.yml', '.yaml'])
const BEAD_PATTERN = /^haxe_ocaml-[a-z0-9]+(\.[0-9]+)*$/

function invariant(condition, message) {
  if (!condition) throw new Error(message)
}

function readText(repoRoot, relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8')
}

function isFile(repoRoot, relativePath) {
  try {
    return fs.statSync(path.join(repoRoot, relativePath)).isFile()
  } catch (error) {
    return false
  }
}

/** Splits the aggregate script exactly as core-test-shards.js does. */
function aggregateCommands(scripts) {
  const script = scripts.test
  invariant(typeof script === 'string', 'package.json is missing scripts.test')
  return script.split(/\s*&&\s*/).map(part => {
    const match = part.match(/^npm run\s+([A-Za-z0-9:._-]+)$/)
    invariant(match, `scripts.test part must be "npm run <script>": ${part}`)
    return match[1]
  })
}

/** Lists every test entry point as a stable `kind:id` key. */
function listEntries(repoRoot, scripts) {
  const entries = []
  for (const name of fs.readdirSync(path.join(repoRoot, 'test')).sort()) {
    if (name.endsWith('.hxml') && isFile(repoRoot, `test/${name}`)) entries.push(`file:test/${name}`)
  }
  for (const name of Object.keys(scripts).sort()) {
    if (name.startsWith('test:')) entries.push(`script:${name}`)
  }
  for (const name of fs.readdirSync(path.join(repoRoot, 'scripts/ci')).sort()) {
    if (name.endsWith('-test.js')) entries.push(`file:scripts/ci/${name}`)
  }
  const portableRoot = path.join(repoRoot, PORTABLE_ROOT)
  if (fs.existsSync(portableRoot)) {
    for (const entry of fs.readdirSync(portableRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) entries.push(`fixture:${PORTABLE_ROOT}/${entry.name}`)
    }
  }
  return entries.sort()
}

/**
 * Returns the npm script names and repository files that a text names.
 * `fromFile` is the referring file, used to resolve bare file names.
 */
function references(repoRoot, text, scriptNames, fromFile) {
  const scripts = new Set()
  const files = new Set()
  for (const match of text.matchAll(/npm\s+(?:run|run-script)\s+(?:-s\s+|--silent\s+)?["']?([A-Za-z0-9:._-]+)/g)) {
    if (scriptNames.has(match[1])) scripts.add(match[1])
  }
  if (/npm\s+(?:run\s+)?test(?![A-Za-z0-9:._-])/.test(text)) scripts.add('test')
  for (const match of text.matchAll(/["'`]([A-Za-z0-9:._-]+:[A-Za-z0-9:._-]+)["'`]/g)) {
    if (scriptNames.has(match[1])) scripts.add(match[1])
  }
  for (const match of text.matchAll(/(?:^|[^A-Za-z0-9_.-])((?:test|scripts|packages|tools|examples)\/[A-Za-z0-9_./-]+\.[A-Za-z]+)/g)) {
    const candidate = path.posix.normalize(match[1])
    if (isFile(repoRoot, candidate)) files.add(candidate)
  }
  if (fromFile) {
    const dir = path.posix.dirname(fromFile)
    for (const match of text.matchAll(/(?:^|[^A-Za-z0-9_-])((?:\.\.?\/)*[A-Za-z0-9_-]+(?:[./][A-Za-z0-9_-]+)*\.(?:hxml|js|sh|cjs|mjs))\b/g)) {
      const candidate = path.posix.normalize(path.posix.join(dir, match[1]))
      if (!candidate.startsWith('..') && isFile(repoRoot, candidate)) files.add(candidate)
      const testCandidate = `test/${path.posix.basename(match[1])}`
      if (match[1].endsWith('.hxml') && isFile(repoRoot, testCandidate)) files.add(testCandidate)
    }
    // A test's main class can start other test builds, so follow it.
    if (fromFile.endsWith('.hxml')) {
      for (const match of text.matchAll(/^\s*(?:-main|--main|--run)\s+([A-Za-z0-9_.]+)/gm)) {
        const candidate = `test/${match[1].replace(/\./g, '/')}.hx`
        if (isFile(repoRoot, candidate)) files.add(candidate)
      }
    }
    for (const match of text.matchAll(/require\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g)) {
      for (const suffix of ['', '.js', '/index.js']) {
        const candidate = path.posix.normalize(path.posix.join(dir, match[1] + suffix))
        if (isFile(repoRoot, candidate)) {
          files.add(candidate)
          break
        }
      }
    }
  }
  return { scripts, files }
}

/**
 * Drops `paths:` and `paths-ignore:` trigger filters from a workflow. Those
 * lists name files that start a workflow when changed, not files it runs.
 */
function withoutPathFilters(text) {
  const kept = []
  let filterIndent = null
  for (const line of text.split('\n')) {
    const indent = line.length - line.trimStart().length
    if (filterIndent !== null) {
      if (line.trim() === '' || (indent >= filterIndent && line.trimStart().startsWith('-'))) continue
      filterIndent = null
    }
    if (/^\s*paths(-ignore)?:\s*$/.test(line)) {
      filterIndent = indent
      continue
    }
    kept.push(line)
  }
  return kept.join('\n')
}

/** Returns the command text that CI runs: workflows, reachable scripts and shell files. */
function ciCommandText(repoRoot, scripts, reachable, workflowTexts) {
  const corpus = [...workflowTexts]
  for (const key of reachable) {
    if (key.startsWith('script:')) corpus.push(scripts[key.slice('script:'.length)] || '')
    else if (key.startsWith('file:') && /\.(sh|js|cjs|mjs)$/.test(key) && isFile(repoRoot, key.slice('file:'.length))) {
      corpus.push(readText(repoRoot, key.slice('file:'.length)))
    }
  }
  return corpus
}

/** True when `command` appears in `corpus` as a whole command, not inside a longer one. */
function containsCommand(corpus, command) {
  for (const text of corpus) {
    let index = text.indexOf(command)
    while (index >= 0) {
      const before = text.slice(0, index)
      const after = text.slice(index + command.length)
      const startsCommand = /(^|[\n;&|(]|run:|['"`])\s*$/.test(before)
      const endsCommand = /^\s*($|[\n;&|)]|['"`])/.test(after) || /^\s+--?[A-Za-z]/.test(after) && !/^\s+-D\b/.test(after)
      if (startsCommand && endsCommand) return true
      index = text.indexOf(command, index + 1)
    }
  }
  return false
}

/**
 * Walks every reference and returns the keys it reaches. Without `roots`,
 * the walk starts from the CI roots; with `roots`, it starts from those keys.
 */
function reachableKeys(repoRoot, scripts, roots = null) {
  const scriptNames = new Set(Object.keys(scripts))
  const reachable = new Set()
  const queue = []
  const visit = key => {
    if (reachable.has(key)) return
    reachable.add(key)
    queue.push(key)
  }
  if (roots) for (const key of roots) visit(key)
  else for (const command of aggregateCommands(scripts)) visit(`script:${command}`)
  const workflowRoot = path.join(repoRoot, '.github/workflows')
  const workflowTexts = []
  for (const name of roots ? [] : fs.readdirSync(workflowRoot).sort()) {
    if (!/\.ya?ml$/.test(name)) continue
    const workflow = `.github/workflows/${name}`
    const text = withoutPathFilters(readText(repoRoot, workflow))
    workflowTexts.push(text)
    const found = references(repoRoot, text, scriptNames, null)
    for (const script of found.scripts) visit(`script:${script}`)
    for (const file of found.files) visit(`file:${file}`)
    // Workflow matrices name scripts as bare YAML list items.
    for (const match of text.matchAll(/^\s*-\s+["']?([A-Za-z0-9:._-]+)["']?\s*$/gm)) {
      if (scriptNames.has(match[1])) visit(`script:${match[1]}`)
    }
  }
  while (queue.length > 0) {
    const key = queue.shift()
    if (key.startsWith('fixture:')) continue
    let text
    let fromFile = null
    if (key.startsWith('script:')) {
      text = scripts[key.slice('script:'.length)] || ''
    } else {
      fromFile = key.slice('file:'.length)
      // The exception list names unreachable tests; it does not run them.
      if (fromFile === EXCEPTIONS_PATH) continue
      if (!TEXT_EXTENSIONS.has(path.extname(fromFile))) continue
      if (!isFile(repoRoot, fromFile)) continue
      text = readText(repoRoot, fromFile)
    }
    const found = references(repoRoot, text, scriptNames, fromFile)
    for (const script of found.scripts) visit(`script:${script}`)
    for (const file of found.files) visit(`file:${file}`)
  }
  if (roots) return reachable
  // A wrapper script is covered when CI already runs exactly the commands it
  // runs, for example `test:x` = `node scripts/ci/x.js` while a workflow calls
  // `node scripts/ci/x.js --out dir`. Each `&&` part must appear as a whole
  // command in CI text, so an added environment variable, define, or argument
  // (a variant CI never runs) keeps the wrapper unreachable. A part that is
  // `npm run <reachable script>` needs no text match. Repeat until stable.
  const corpus = ciCommandText(repoRoot, scripts, reachable, workflowTexts)
  let changed = true
  while (changed) {
    changed = false
    for (const name of scriptNames) {
      const key = `script:${name}`
      if (reachable.has(key)) continue
      const parts = scripts[name].split(/\s*&&\s*/).map(part => part.trim())
      const covered = parts.every(part => {
        const npmRun = part.match(/^npm\s+run\s+(?:-s\s+)?([A-Za-z0-9:._-]+)$/)
        if (npmRun) return reachable.has(`script:${npmRun[1]}`)
        const found = references(repoRoot, part, scriptNames, null)
        if (found.scripts.size + found.files.size === 0) return false
        return containsCommand(corpus, part)
      })
      if (covered) {
        reachable.add(key)
        corpus.push(scripts[name])
        changed = true
      }
    }
  }
  return reachable
}

function loadExceptions(repoRoot) {
  const manifest = JSON.parse(readText(repoRoot, EXCEPTIONS_PATH))
  invariant(manifest.schema === SCHEMA, `${EXCEPTIONS_PATH} schema must be ${SCHEMA}`)
  invariant(manifest.unreachable && typeof manifest.unreachable === 'object', `${EXCEPTIONS_PATH} needs an unreachable object`)
  for (const [key, record] of Object.entries(manifest.unreachable)) {
    invariant(record && typeof record.reason === 'string' && record.reason.trim() !== '', `${key} needs a reason`)
    invariant(typeof record.bead === 'string' && BEAD_PATTERN.test(record.bead), `${key} needs an owning bead id`)
  }
  return manifest.unreachable
}

/** Returns the full inventory and every contract violation. */
function evaluate(repoRoot = process.cwd()) {
  const scripts = JSON.parse(readText(repoRoot, 'package.json')).scripts
  const entries = listEntries(repoRoot, scripts)
  const reachable = reachableKeys(repoRoot, scripts)
  const portableReachable = reachable.has(`script:${PORTABLE_COMMAND}`)
  const isReachable = key => {
    if (key.startsWith('fixture:')) {
      return portableReachable && isFile(repoRoot, `${key.slice('fixture:'.length)}/build.hxml`)
    }
    return reachable.has(key)
  }
  const unreachable = entries.filter(key => !isReachable(key))
  const exceptions = loadExceptions(repoRoot)
  const entrySet = new Set(entries)
  // An entry that only a listed exception runs, such as the `.hxml` file of a
  // listed npm script, shares that exception and needs no entry of its own.
  // Only files share an exception; a script always needs its own entry.
  const accounted = new Set(
    [...reachableKeys(repoRoot, scripts, Object.keys(exceptions).filter(key => entrySet.has(key)))].filter(
      key => key.startsWith('file:') || Object.prototype.hasOwnProperty.call(exceptions, key)
    )
  )
  const errors = []
  for (const key of unreachable) {
    if (!accounted.has(key)) errors.push(`no CI path reaches ${key}; wire it into npm test, a shard, or a workflow, or list it in ${EXCEPTIONS_PATH} with a reason and bead`)
  }
  // A script that names a missing test file can never pass, and a reference
  // check would otherwise treat it as merely unreachable.
  for (const [name, body] of Object.entries(scripts)) {
    for (const match of body.matchAll(/(?:^|[\s'"=])((?:test|scripts)\/[A-Za-z0-9_./-]+\.(?:hxml|js|sh))(?![A-Za-z0-9_./-])/g)) {
      if (!isFile(repoRoot, match[1])) errors.push(`npm script ${name} runs ${match[1]}, which does not exist`)
    }
  }
  for (const key of Object.keys(exceptions)) {
    if (!entrySet.has(key)) errors.push(`${EXCEPTIONS_PATH} lists ${key}, which no longer exists`)
    else if (isReachable(key)) errors.push(`${EXCEPTIONS_PATH} lists ${key}, which CI now reaches; remove the exception`)
  }
  return { entries, unreachable, errors, listed: Object.keys(exceptions).length }
}

function main() {
  const listOnly = process.argv.includes('--list-unreachable')
  const result = evaluate()
  if (listOnly) {
    for (const key of result.unreachable) console.log(key)
    return
  }
  if (result.errors.length > 0) {
    for (const error of result.errors) console.error(`[test-entry-reachability] ERROR: ${error}`)
    process.exitCode = 1
    return
  }
  console.log(`[test-entry-reachability] PASS entries=${result.entries.length} reachable=${result.entries.length - result.unreachable.length} unreachable=${result.unreachable.length} exceptions=${result.listed}`)
}

if (require.main === module) main()

module.exports = { evaluate, listEntries, references, reachableKeys, SCHEMA }
