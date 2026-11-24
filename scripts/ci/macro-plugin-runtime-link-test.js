#!/usr/bin/env node
// Check that the hxhx host links every OCaml runtime unit a project-macro plugin is built with.
//
// Why
// - A project-macro plugin is compiled by the Stage3 emitter against the runtime sources in
//   packages/reflaxe.ocaml/std/runtime (all `.ml` files except haxe_CallStack.ml, as
//   EmitterStage.stage3RuntimePaths selects). When the host loads the plugin, Dynlink takes
//   these units from the host. A unit the host did not link fails the load with
//   "no implementation available for <Unit>".
// - The linker adds a library unit to the host only when linked host code names it, and dune
//   links only the executable modules reachable from the main module. HxDynamicMethods was
//   the first unit that only Stage3-emitted code names (commit 6a619afa6), so every plugin
//   failed to load (haxe_ocaml-q022l).
//
// What
// - Follows module references from the host's main module (`out.ml` in the host's generated
//   OCaml, packages/hxhx/bootstrap_out by default) through the host modules and the runtime
//   sources, as the linker does, and fails for each plugin runtime unit the host would not link.
// - A reference is a capitalized module name followed by `.`, or the target of `open` or
//   `include`, outside strings, character literals, and comments.
// - After the check, a negative case removes the plugin-only reference from a copy of the
//   runtime and requires the check to report HxDynamicMethods.
//
// Options: --host-dir <dir> (generated host modules), --runtime-dir <dir> (runtime sources).
const assert = require('assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '../..')

function option(name, fallback) {
  const index = process.argv.indexOf(name)
  return index >= 0 && process.argv[index + 1] ? path.resolve(process.argv[index + 1]) : fallback
}

const hostDir = option('--host-dir', path.join(root, 'packages/hxhx/bootstrap_out'))
const runtimeDir = option('--runtime-dir', path.join(root, 'packages/reflaxe.ocaml/std/runtime'))
const loaderFile = 'HxHxMacroModuleDynlink.ml'

function moduleName(file) {
  const base = path.basename(file).replace(/\.ml$/, '')
  return base.charAt(0).toUpperCase() + base.slice(1)
}

// Module sources keyed by module name; a sharded snapshot module is read from its `.ml.parts` list.
function readModules(dir) {
  const modules = new Map()
  for (const entry of fs.readdirSync(dir)) {
    const file = path.join(dir, entry)
    if (entry.endsWith('.ml') && fs.statSync(file).isFile()) {
      modules.set(moduleName(entry), () => fs.readFileSync(file, 'utf8'))
    } else if (entry.endsWith('.ml.parts')) {
      const name = moduleName(entry.replace(/\.parts$/, ''))
      if (!modules.has(name))
        modules.set(name, () =>
          fs
            .readFileSync(file, 'utf8')
            .split('\n')
            .map(line => line.trim())
            .filter(line => line.length > 0)
            .map(part => fs.readFileSync(path.join(dir, path.basename(part)), 'utf8'))
            .join(''),
        )
    }
  }
  return modules
}

// OCaml text without strings, character literals, and (nested) comments.
function codeOnly(text) {
  let out = ''
  let depth = 0
  let index = 0
  const skipString = () => {
    index++
    while (index < text.length && text[index] !== '"') index += text[index] === '\\' ? 2 : 1
    index++
  }
  while (index < text.length) {
    const char = text[index]
    const next = text[index + 1]
    if (char === '(' && next === '*') {
      depth++
      index += 2
    } else if (depth > 0 && char === '*' && next === ')') {
      depth--
      index += 2
    } else if (char === '"') {
      skipString()
      if (depth === 0) out += '""'
    } else if (depth > 0) {
      index++
    } else if (char === "'" && text[index + 2] === "'") {
      index += 3
    } else if (char === "'" && next === '\\') {
      const end = text.indexOf("'", index + 2)
      index = end > 0 && end - index <= 5 ? end + 1 : index + 1
    } else {
      out += char
      index++
    }
  }
  return out
}

function references(text) {
  const code = codeOnly(text)
  const names = new Set()
  for (const match of code.matchAll(/(?<![A-Za-z0-9_'.])([A-Z][A-Za-z0-9_']*)\s*\./g)) names.add(match[1])
  for (const match of code.matchAll(/\b(?:open|include)!?\s+([A-Z][A-Za-z0-9_']*)/g)) names.add(match[1])
  return names
}

/** The plugin runtime units the host would not link, sorted. */
function unlinkedPluginUnits(host, runtime) {
  if (!host.has('Out')) throw new Error(`no host main module out.ml in ${hostDir}`)
  const pluginUnits = [...runtime.keys()].filter(name => name !== 'Haxe_CallStack')
  const linked = new Set()
  const work = [['host', 'Out']]
  while (work.length > 0) {
    const [kind, name] = work.pop()
    const key = kind + ':' + name
    if (linked.has(key)) continue
    linked.add(key)
    const source = (kind === 'host' ? host : runtime).get(name)()
    for (const reference of references(source)) {
      // Inside the runtime library a name is a library unit; host code sees its own modules first.
      if (kind === 'runtime' && runtime.has(reference)) work.push(['runtime', reference])
      else if (kind === 'host' && host.has(reference)) work.push(['host', reference])
      else if (runtime.has(reference)) work.push(['runtime', reference])
    }
  }
  return pluginUnits.filter(name => !linked.has('runtime:' + name)).sort()
}

const host = readModules(hostDir)

const missing = unlinkedPluginUnits(host, readModules(runtimeDir))
if (missing.length > 0) {
  console.error(
    `The hxhx host does not link these runtime units, so project-macro plugins that use them fail to load: ${missing.join(', ')}.\n` +
      `Name each one in plugin_only_runtime_units in ${path.join(runtimeDir, loaderFile)}.`,
  )
  process.exit(1)
}
// Negative case: without the loader's plugin-only reference, HxDynamicMethods is not linked.
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-plugin-runtime-link-'))
try {
  for (const entry of fs.readdirSync(runtimeDir))
    if (entry.endsWith('.ml')) fs.copyFileSync(path.join(runtimeDir, entry), path.join(temporary, entry))
  const loader = fs.readFileSync(path.join(temporary, loaderFile), 'utf8')
  const withoutReference = loader.replace(/^let plugin_only_runtime_units\b[^\n]*\n/m, '')
  if (withoutReference === loader) throw new Error(`${loaderFile} no longer declares plugin_only_runtime_units`)
  fs.writeFileSync(path.join(temporary, loaderFile), withoutReference)
  assert.deepEqual(
    unlinkedPluginUnits(host, readModules(temporary)),
    ['HxDynamicMethods'],
    'the check must report HxDynamicMethods when the loader does not name it',
  )
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}

console.log('MACRO_PLUGIN_RUNTIME_LINK:PASS')
