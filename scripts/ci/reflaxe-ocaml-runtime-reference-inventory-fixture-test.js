#!/usr/bin/env node

/**
 * Proves that the migration inventory is deterministic and fails on growth.
 *
 * These fixtures use small authored Haxe snippets. They do not generate their
 * expected records with the production checker, so a scanner regression cannot
 * silently rewrite its own oracle.
 */

const assert = require('node:assert/strict')
const {
	discoverFromSourceMap,
	buildInventory,
	compareInventory,
	validateReviewBead,
} = require('./reflaxe-ocaml-runtime-reference-inventory')

const fixturePath = 'packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/FixtureSyntax.hx'
const baselineSource = `
class FixtureSyntax {
  static function build() {
    // Comments and ordinary policy strings are not target-reference constructors:
    // OcamlExpr.EIdent("HxCommentOnly")
    final policyName = "HxPolicyOnly";
    final expr = OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set");
    final singleQuoted = OcamlExpr.EIdent('HxSingleQuoted');
    final typ = OcamlTypeExpr.TIdent("int HxArray.t");
    final pat = OcamlPat.PConstructor("HxOption.Some", []);
    lines.push("  HxType.class_ name;");
    checked.addLegacyRuntimeUse("legacy:ctor", "HxType.register_class_ctor");
    final getToken = checked.legacyRuntimeToken("legacy:get", "HxArray.get");
    checked.addRuntimeUse("checked:set", revision, "HxArray.set");
    final unqualifiedRaw = ERaw(otherCode);
    return OcamlExpr.ERaw(userCode);
  }
}
`

const sourceMap = source => new Map([[fixturePath, source]])
const records = discoverFromSourceMap(sourceMap(baselineSource))
assert.deepStrictEqual(records.map(record => [record.domain, record.construction, record.symbol]), [
	['expression', 'EField(EIdent)', 'HxArray.set'],
	['expression', 'EIdent', 'HxSingleQuoted'],
	['type', 'TIdent', 'HxArray.t'],
	['pattern', 'PConstructor', 'HxOption.Some'],
	['generated-text', 'lines.push', 'HxType.class_'],
	['generated-text', 'addLegacyRuntimeUse', 'HxType.register_class_ctor'],
	['generated-text', 'legacyRuntimeToken', 'HxArray.get'],
	['raw-boundary', 'ERaw', null],
	['raw-boundary', 'OcamlExpr.ERaw', null],
])

const first = buildInventory(records, 'haxe_ocaml-fixture')
const second = buildInventory(discoverFromSourceMap(sourceMap(baselineSource)), 'haxe_ocaml-fixture')
assert.deepStrictEqual(second, first, 'clean repeated discovery must be deterministic')
assert.deepStrictEqual(compareInventory(first, records), [])

const grownSource = baselineSource.replace(
	'final typ =',
	'final duplicate = OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set");\n    final typ =',
)
const growthFailures = compareInventory(first, discoverFromSourceMap(sourceMap(grownSource)))
assert(growthFailures.some(failure => failure.includes('new legacy runtime reference')))
assert(growthFailures.some(failure => failure.includes('FixtureSyntax.hx:')))
assert(growthFailures.some(failure => failure.includes('HxArray.set')))

const changedSource = baselineSource.replace('HxOption.Some', 'HxOption.None')
const changeFailures = compareInventory(first, discoverFromSourceMap(sourceMap(changedSource)))
assert(changeFailures.some(failure => failure.includes('new legacy runtime reference')))
assert(changeFailures.some(failure => failure.includes('still lists a removed or changed legacy reference')))

assert.throws(() => validateReviewBead(null), /requires --review-bead/)
assert.throws(() => validateReviewBead('notes-only'), /requires --review-bead/)
validateReviewBead('haxe_ocaml-0uwin.27')

console.log('REFLAXE_OCAML_RUNTIME_REFERENCE_INVENTORY_FIXTURES:PASS')
