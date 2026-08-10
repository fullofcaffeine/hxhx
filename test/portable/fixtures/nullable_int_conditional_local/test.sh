#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
const sourceConversions = report.localConversions.filter(conversion =>
	conversion.source.file === 'src/Main.hx'
	&& conversion.functionId.includes('|function|exercise|'))

// The local plan belongs to exercise(), which contains the complete closure
// tree. The nested read() function has a separate control/call identity, but it
// must not replace the owner recorded on these local carrier conversions.
if (sourceConversions.length === 0
	|| sourceConversions.some(conversion =>
		conversion.functionId.includes('|nested-function|')
		|| conversion.pipelineRevision !== 'ocaml-function-plans-v95')) {
	throw new Error('nested local conversions did not retain their whole-tree root plan owner')
}

const assignments = sourceConversions.filter(conversion =>
	conversion.role === 'assignment'
	&& conversion.outputSemanticTypeId === 'Null<Int>')
const assignmentKinds = new Set(assignments.map(conversion => conversion.conversion))
if (assignments.length !== 2
	|| !assignmentKinds.has('preserve-nullable-int-carrier')
	|| !assignmentKinds.has('box-exact-int-to-nullable-int')) {
	throw new Error('the conditional did not seal both nullable and exact-Int branches')
}

const boxed = assignments.find(conversion => conversion.conversion === 'box-exact-int-to-nullable-int')
if (boxed.unsafeOperation?.operation !== 'obj-repr-exact-int')
	throw new Error('the exact Int branch has no checked carrier-crossing proof')

const checkedRead = sourceConversions.find(conversion =>
	conversion.role === 'read'
	&& conversion.inputSemanticTypeId === 'Null<Int>'
	&& conversion.outputSemanticTypeId === 'Int'
	&& conversion.conversion === 'checked-unbox-nullable-int')
if (!checkedRead || checkedRead.unsafeOperation?.operation !== 'checked-nullable-int-unwrap')
	throw new Error('count + 1 did not seal its checked nullable-Int read')
NODE

echo "NULLABLE_INT_CONDITIONAL_LOCAL_PLAN:PASS"
