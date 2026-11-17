#!/usr/bin/env node
'use strict'

/**
 * Representation conformance matrix for reflaxe.ocaml.
 *
 * Why
 *   reflaxe.ocaml carries some Haxe values as native OCaml values (int, float, bool, records,
 *   variants) and others as Obj.t (Dynamic, type parameters, Null<T>, anonymous fields). A
 *   value that crosses from one place to another may need a conversion. Missing conversions
 *   caused the bootstrap break fixed in PR #195 and silent wrong output (bead
 *   haxe_ocaml-9cqxj). This matrix measures that class directly: every value type crosses
 *   every kind of boundary, and the native result is compared with upstream Haxe's interpreter.
 *   It is milestone A2 of docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md.
 *
 * How
 *   For each value type, one program passes a sample value through each boundary and prints
 *   the result with Std.string. Upstream `haxe --interp` gives the expected lines. The same
 *   program is compiled with reflaxe.ocaml and run. When a row does not compile or build, each
 *   of its cells is compiled alone, so one failure does not hide the others.
 *
 * Usage
 *   node scripts/reflaxe-ocaml/representation-matrix.js [--out DIR] [--jobs N] [--only VALUE]... [--boundary ID]...
 *   Prints `REPRESENTATION_MATRIX: ...` and writes report.json and a Markdown table to DIR.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn } = require('child_process')

const root = path.resolve(__dirname, '../..')

/** Value types: Haxe type, a sample expression, and how to print a value of that type. */
const VALUES = [
  { id: 'int', type: 'Int', sample: '42' },
  { id: 'float', type: 'Float', sample: '1.5' },
  { id: 'bool', type: 'Bool', sample: 'true' },
  { id: 'string', type: 'String', sample: '"hi"' },
  { id: 'null_int', type: 'Null<Int>', sample: '(42 : Null<Int>)' },
  { id: 'null_int_null', type: 'Null<Int>', sample: '(null : Null<Int>)' },
  { id: 'null_float', type: 'Null<Float>', sample: '(1.5 : Null<Float>)' },
  { id: 'null_bool', type: 'Null<Bool>', sample: '(true : Null<Bool>)' },
  // Enums print through a typed switch: Std.string of an enum value is itself wrong natively
  // (haxe_ocaml-oxjcd), and that bug would hide every boundary result in these rows.
  { id: 'enum_const', type: 'Color', sample: 'Green', print: v => `showColor(${v})` },
  { id: 'enum_args', type: 'Color', sample: 'Blue(2)', print: v => `showColor(${v})` },
  { id: 'null_enum', type: 'Null<Color>', sample: '(Green : Null<Color>)', print: v => `(${v} == null ? "null" : showColor(${v}))` },
  { id: 'class', type: 'Box', sample: 'new Box(3)' },
  { id: 'anon', type: '{a:Int}', sample: '{a: 1}' },
  // Arrays print through join: Std.string of an array does not build natively yet (Unbound value Array.toString).
  { id: 'array', type: 'Array<Int>', sample: '[1, 2]', print: v => `"[" + ${v}.join(",") + "]"` },
  { id: 'function', type: '(Int->Int)', sample: '(x:Int) -> x + 1', print: v => `${v}(1)` },
  { id: 'dynamic', type: 'Dynamic', sample: '(42 : Dynamic)' }
]

/** Boundaries: Haxe statements that take the sample through one crossing into a value named `out`. */
const BOUNDARIES = [
  { id: 'local', body: v => `var out:${v.type} = ${v.sample};` },
  { id: 'static_field', members: v => `static var sField:${v.type} = ${v.sample};`, body: () => 'var out = sField;' },
  { id: 'instance_field', members: v => `var iField:${v.type};`, body: v => `var self = new Main(); self.iField = ${v.sample}; var out = self.iField;` },
  { id: 'argument', members: v => `static function pass(x:${v.type}):${v.type} return x;`, body: v => `var out = pass(${v.sample});` },
  { id: 'return', members: v => `static function make():${v.type} return ${v.sample};`, body: () => 'var out = make();' },
  { id: 'optional_argument', members: v => `static function opt(?x:${v.type}):${v.type} return x;`, body: v => `var out = opt(${v.sample});` },
  { id: 'generic_function', members: () => 'static function same<T>(x:T):T return x;', body: v => `var out:${v.type} = same(${v.sample});` },
  { id: 'generic_class', body: v => `var holder = new Holder<${v.type}>(${v.sample}); var out = holder.value;` },
  { id: 'dynamic', body: v => `var d:Dynamic = ${v.sample}; var out:${v.type} = d;` },
  // The value is observed while it is Dynamic. It first sits in a typed local, so the conversion starts from the
  // value's own carrier and not from a literal. Haxe does not define how a function prints, so that row skips it.
  {
    id: 'dynamic_observed',
    body: v => `var source:${v.type} = ${v.sample}; var out:Dynamic = source;`,
    print: () => 'Std.string(out)',
    skip: v => v.id === 'function'
  },
  { id: 'array_dynamic', body: v => `var items:Array<Dynamic> = [${v.sample}]; var out:${v.type} = items[0];` },
  { id: 'anon_field', body: v => `var box:{v:${v.type}} = {v: ${v.sample}}; var out = box.v;` },
  { id: 'closure_capture', body: v => `var captured:${v.type} = ${v.sample}; var get = () -> captured; var out = get();` },
  {
    id: 'method_value',
    members: v => `function keep(x:${v.type}):${v.type} return x;`,
    body: v => `var self = new Main(); var f:${v.type}->${v.type} = self.keep; var out = f(${v.sample});`
  },
  { id: 'callback_argument', members: v => `static function call(f:${v.type}->${v.type}, x:${v.type}):${v.type} return f(x);`, body: v => `var out = call(y -> y, ${v.sample});` }
]

function printValue(value, name) {
  return value.print ? value.print(name) : name
}

function program(value, boundaries) {
  const members = []
  const seen = new Set()
  for (const boundary of boundaries) {
    if (!boundary.members) continue
    const text = boundary.members(value)
    if (!seen.has(text)) {
      seen.add(text)
      members.push(`\t${text}`)
    }
  }
  const cells = boundaries
    .filter(boundary => !(boundary.skip && boundary.skip(value)))
    .map(boundary => `\t\t{\n\t\t\t${boundary.body(value)}\n\t\t\tSys.println("${boundary.id}=" + Std.string(${boundary.print ? boundary.print() : printValue(value, 'out')}));\n\t\t}`)
  return `enum Color {
	Red;
	Green;
	Blue(n:Int);
}

class Box {
	public var v:Int;

	public function new(v:Int)
		this.v = v;

	public function toString():String
		return "Box(" + v + ")";
}

class Holder<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;
}

class Main {
${members.join('\n')}

	static function showColor(c:Color):String
		return switch c {
			case Red: "Red";
			case Green: "Green";
			case Blue(n): "Blue(" + n + ")";
		}

	public function new() {}

	static function main() {
${cells.join('\n')}
	}
}
`
}

function exec(command, args, options) {
  return new Promise(resolve => {
    const child = spawn(command, args, { cwd: options.cwd, env: process.env })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', chunk => (stdout += chunk))
    child.stderr.on('data', chunk => (stderr += chunk))
    const timer = setTimeout(() => child.kill('SIGKILL'), options.timeoutMs)
    child.on('close', (code, signal) => {
      clearTimeout(timer)
      resolve({ code, signal, stdout, stderr })
    })
  })
}

/** A counting semaphore: every compile, from rows and from per-cell fallbacks, shares the same slots. */
let slots = 1
const waiting = []
async function acquire() {
  if (slots > 0) {
    slots--
    return
  }
  await new Promise(resolve => waiting.push(resolve))
}
function release() {
  const next = waiting.shift()
  if (next) next()
  else slots++
}

/** Compile and run one program; returns expected and actual lines, or the stage that failed. */
async function check(dir, source, haxe) {
  await acquire()
  try {
    return await checkUnlocked(dir, source, haxe)
  } finally {
    release()
  }
}

async function checkUnlocked(dir, source, haxe) {
  fs.rmSync(dir, { recursive: true, force: true })
  fs.mkdirSync(path.join(dir, 'src'), { recursive: true })
  fs.writeFileSync(path.join(dir, 'src', 'Main.hx'), source)
  const expected = await exec(haxe, ['-cp', 'src', '-main', 'Main', '--interp'], { cwd: dir, timeoutMs: 120000 })
  if (expected.code !== 0) return { stage: 'upstream', detail: expected.stdout + expected.stderr }
  const compile = await exec(
    haxe,
    ['-cp', 'src', '-cp', path.join(root, 'packages/reflaxe.ocaml/src'), '-main', 'Main', '--no-output', '-lib', 'reflaxe.ocaml', '-D', 'no-traces', '-D', 'ocaml_output=out'],
    { cwd: dir, timeoutMs: 600000 }
  )
  const exe = path.join(dir, 'out/_build/default/out.exe')
  if (compile.code !== 0) return { stage: 'compile', detail: compile.stdout + compile.stderr, expected: expected.stdout }
  if (!fs.existsSync(exe)) return { stage: 'ocaml-build', detail: compile.stdout + compile.stderr, expected: expected.stdout }
  const actual = await exec(exe, [], { cwd: dir, timeoutMs: 60000 })
  return { stage: actual.code === 0 ? 'ran' : 'runtime', expected: expected.stdout, actual: actual.stdout, detail: actual.stderr }
}

function lines(text) {
  const map = new Map()
  for (const line of (text || '').split('\n')) {
    const at = line.indexOf('=')
    if (at > 0) map.set(line.slice(0, at), line.slice(at + 1))
  }
  return map
}

function firstError(detail) {
  const text = detail || ''
  const match = text.match(/Error[^\n]*\n?[^\n]*/) || text.match(/[^\n]*(exception|Uncaught)[^\n]*/i)
  return (match ? match[0] : text.split('\n').find(line => line.trim()) || '').trim().slice(0, 200)
}

async function runRow(value, outDir, haxe) {
  const results = {}
  const row = await check(path.join(outDir, value.id), program(value, BOUNDARIES), haxe)
  if (row.stage === 'ran' || row.stage === 'runtime') {
    const expected = lines(row.expected)
    const actual = lines(row.actual)
    for (const boundary of BOUNDARIES) {
      if (boundary.skip && boundary.skip(value)) {
        results[boundary.id] = { status: 'skip' }
        continue
      }
      const want = expected.get(boundary.id)
      const got = actual.get(boundary.id)
      results[boundary.id] = got === want ? { status: 'pass' } : got === undefined ? { status: 'runtime', detail: firstError(row.detail) } : { status: 'wrong', expected: want, actual: got }
    }
    return results
  }
  await Promise.all(
    BOUNDARIES.map(async boundary => {
      if (boundary.skip && boundary.skip(value)) {
        results[boundary.id] = { status: 'skip' }
        return
      }
      const cell = await check(path.join(outDir, `${value.id}__${boundary.id}`), program(value, [boundary]), haxe)
      if (cell.stage === 'ran') {
        const want = lines(cell.expected).get(boundary.id)
        const got = lines(cell.actual).get(boundary.id)
        results[boundary.id] = got === want ? { status: 'pass' } : { status: 'wrong', expected: want, actual: got }
      } else {
        results[boundary.id] = { status: cell.stage, detail: firstError(cell.detail) }
      }
    })
  )
  return results
}

async function main() {
  const args = process.argv.slice(2)
  let out = path.join(root, '.tmp/representation-matrix')
  let jobs = Math.max(1, Math.min(4, os.cpus().length - 1))
  const only = []
  const onlyBoundaries = []
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--out') out = path.resolve(args[++index])
    else if (args[index] === '--jobs') jobs = Number(args[++index])
    else if (args[index] === '--only') only.push(args[++index])
    else if (args[index] === '--boundary') onlyBoundaries.push(args[++index])
    else throw new Error(`unknown argument: ${args[index]}`)
  }
  const haxe = process.env.HAXE_BIN || 'haxe'
  const values = only.length > 0 ? VALUES.filter(value => only.includes(value.id)) : VALUES
  if (onlyBoundaries.length > 0) BOUNDARIES.splice(0, BOUNDARIES.length, ...BOUNDARIES.filter(boundary => onlyBoundaries.includes(boundary.id)))
  fs.mkdirSync(out, { recursive: true })
  const matrix = {}
  slots = jobs
  await Promise.all(
    values.map(async value => {
      matrix[value.id] = await runRow(value, out, haxe)
      console.log(`[representation-matrix] ${value.id}: ${Object.values(matrix[value.id]).filter(cell => cell.status === 'pass').length}/${BOUNDARIES.length}`)
    })
  )
  const counts = {}
  for (const value of values) for (const cell of Object.values(matrix[value.id])) counts[cell.status] = (counts[cell.status] || 0) + 1
  const total = values.length * BOUNDARIES.length - (counts.skip || 0)
  const header = `| value \\ boundary | ${BOUNDARIES.map(boundary => boundary.id).join(' | ')} |\n|---|${BOUNDARIES.map(() => '---').join('|')}|\n`
  const symbol = { pass: 'ok', wrong: 'WRONG', compile: 'refused', 'ocaml-build': 'build', runtime: 'crash', upstream: 'n/a', skip: '-' }
  const rows = values.map(value => `| ${value.id} | ${BOUNDARIES.map(boundary => symbol[matrix[value.id][boundary.id].status]).join(' | ')} |`).join('\n')
  fs.writeFileSync(path.join(out, 'matrix.md'), header + rows + '\n')
  fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify({ values: values.map(v => v.id), boundaries: BOUNDARIES.map(b => b.id), counts, matrix }, null, 2))
  console.log(`REPRESENTATION_MATRIX: cells=${total} pass=${counts.pass || 0} (${((100 * (counts.pass || 0)) / total).toFixed(1)}%) wrong=${counts.wrong || 0} ocaml_build=${counts['ocaml-build'] || 0} compile=${counts.compile || 0} crash=${counts.runtime || 0} upstream_reject=${counts.upstream || 0}`)
  console.log(`[representation-matrix] table: ${path.relative(root, path.join(out, 'matrix.md'))}`)
}

main().catch(error => {
  console.error(`[representation-matrix] ERROR: ${error.message}`)
  process.exit(1)
})
