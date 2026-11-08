#!/usr/bin/env bash
set -euo pipefail
"${HAXE_BIN:-haxe}" -cp src -main Main --interp > out/upstream.stdout
diff -u expected.stdout out/upstream.stdout
node - out/ocaml_lowering_report.json <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
// Haxe emits the second case body twice. Each copy calls its own `check` local,
// so the plan must keep two invocations of the same source call.
const invocations = report.calls.filter(call => call.callbackInvocation != null && call.kind === 'typed-function-value');
const bySource = new Map();
for (const call of invocations) {
 const key = `${call.source.file}:${call.source.min}:${call.source.max}`;
 bySource.set(key, [...(bySource.get(key) ?? []), call]);
}
const copied = [...bySource.values()].filter(calls => calls.length > 1);
assert.equal(copied.length, 1, 'exactly one source call must have one plan per emitted copy');
const [first, second] = copied[0];
assert.notEqual(first.id, second.id, 'each copy needs its own call identity');
assert.notEqual(first.calleeId, second.calleeId, 'each copy calls its own local');
NODE
