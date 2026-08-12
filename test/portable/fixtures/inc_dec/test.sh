#!/usr/bin/env bash
set -euo pipefail

node - out/Main.ml out/ocaml_lowering_report.json <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))

const admission = report.controlAdmissions.find(entry =>
	entry.functionId.includes('|Counter|instance|function|loopTo|'))
const result = report.functionResultBoundaries.find(entry => entry.functionId === admission?.functionId)
const callable = report.callableBoundaries.find(entry => entry.functionId === admission?.functionId)
const returns = admission?.families?.find(entry => entry.family === 'return')
if (report.schemaVersion !== 84
	|| returns?.status !== 'admitted'
	|| returns.occurrenceCount !== 1
	|| returns.decisionCount !== 1
	|| result?.source !== 'callable-boundary'
	|| result.callableBoundaryId !== callable?.id
	|| callable.kind !== 'direct-instance-haxe-method'
	|| result.result?.inputSemanticTypeId !== 'Int'
	|| result.result?.outputCarrierTypeId !== 'int'
	|| report.functionResultBoundaries.some(entry =>
		entry.functionId === admission.functionId
		&& entry.source === 'non-generic-instance-exact-int-declaration')) {
	throw new Error('Counter.loopTo did not reuse its existing instance-call boundary as the sole exact-Int result owner')
}

const start = source.indexOf('let counter_loopTo =')
const end = source.indexOf('\nlet ', start + 1)
const body = source.slice(start, end)
if (start < 0
	|| end < 0
	|| !body.includes('HxRuntime.Hx_return')
	|| body.includes('__fallback_result')) {
	throw new Error('Counter.loopTo still uses legacy result recovery')
}
NODE

echo "INC_DEC_INSTANCE_RESULT_BOUNDARY:PASS"
