#!/usr/bin/env node
const assert = require('node:assert/strict')
const {violationsInText} = require('./no-dynamic-check')
const file = 'packages/hxhx-core/src/backend/PolicyFixture.hx'
function labels(source) {
  return violationsInText(file, source).map(value => value.label)
}

// These are the actual kinds of literal text rejected by PR92 Guardrails.
for (const source of [
  'return "core:Dynamic";',
  'case "haxe.NativeStackTrace#static:callStack()->nominal:Any#0": CallStack;',
  'out.push("->representation() == hxhx::managed::ArrayRepresentation::Dynamic) {");',
  "return 'literal :Dynamic and <Any>';",
  'return "escaped quote \\\" :Dynamic";',
  'return "${(null:Dynamic)}";',
  "return '$${(null:Dynamic)}';",
  'final pattern = ~/:Dynamic|<Any>|\\/untyped __ocaml__/g;',
  '/* heading\nvar forbidden:Dynamic;\n*/\nvar safe:Int;',
  'var safe:Int; // example:Dynamic',
]) assert.deepEqual(labels(source), [], source)

for (const [source, expected] of [
  ['var value:Dynamic;', 'typed_dynamic'],
  ['var value:Any;', 'typed_any'],
  ['var value:Std.Any;', 'typed_any'],
  ['var value:Array<Dynamic>;', 'generic_dynamic'],
  ['var value:Array<Std.Any>;', 'generic_any'],
  ['try work() catch (error:Dynamic) {}', 'typed_dynamic'],
  ['untyped __ocaml__("native source");', 'untyped_ocaml'],
  ['var text = "safe"; var forbidden:Dynamic;', 'typed_dynamic'],
  ['/* ignored :Any */ var forbidden:Dynamic;', 'typed_dynamic'],
  ['final pattern = ~/:Any/g; var forbidden:Dynamic;', 'typed_dynamic'],
  ["return '${(null:Dynamic)}';", 'typed_dynamic'],
  ["return '${{field: \"x\", value: (null:Any)}}';", 'typed_any'],
  ["return '${'nested ${(null:Dynamic)}'}';", 'typed_dynamic'],
  ["return '${ /* } */ (null:Any)}';", 'typed_any'],
  ["return '$$${(null:Dynamic)}';", 'typed_dynamic'],
]) assert.deepEqual(labels(source), [expected], source)

const positioned = violationsInText(file, '/* :Dynamic\n */\nvar text = "literal :Any";\nvar value:Dynamic;')
assert.equal(positioned.length, 1)
assert.equal(positioned[0].line, 4)
assert.equal(positioned[0].source, 'var value:Dynamic;')
console.log('DYNAMIC_POLICY_LEXICAL_BOUNDARY:PASS')
