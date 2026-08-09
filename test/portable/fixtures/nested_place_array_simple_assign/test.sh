#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
const sourcePlans = report.plans.filter(plan => plan.source.file === 'src/Main.hx')
const assignmentPlans = sourcePlans.filter(plan => plan.nodeKind === 'array-simple-assignment')

if (assignmentPlans.length !== 1)
	throw new Error(`expected one source array assignment plan, found ${assignmentPlans.length}`)

const plan = assignmentPlans[0]
const expectedRoles = ['receiver', 'index', 'right-hand-side', 'store', 'result']
const actualRoles = plan.schedule.map(occurrence => occurrence.role)
if (JSON.stringify(actualRoles) !== JSON.stringify(expectedRoles)
	|| plan.schedule.some(occurrence => occurrence.occurrenceCount !== 1)) {
	throw new Error('the nested assignment did not preserve its exact once-only evaluation schedule')
}

if (plan.semanticTypeId !== 'Int'
	|| plan.carrierTypeId !== 'int'
	|| plan.place.kind !== 'array-element'
	|| plan.place.receiverSemanticTypeId !== 'Array<Int>'
	|| plan.place.receiverCarrierTypeId !== 'int HxArray.t'
	|| plan.place.indexSemanticTypeId !== 'Int'
	|| plan.place.indexCarrierTypeId !== 'int'
	|| plan.conversion !== 'identity'
	|| plan.result !== 'assigned-value') {
	throw new Error('the nested assignment plan changed its typed array, Int carrier, or result contract')
}

const expectedRuntime = `${plan.originId}:runtime:haxe-array-element-set`
if (plan.runtimeRequirementIds.length !== 1 || plan.runtimeRequirementIds[0] !== expectedRuntime)
	throw new Error('the nested assignment has no exact HxArray.set runtime requirement')
NODE

echo "NESTED_PLACE_ARRAY_SIMPLE_ASSIGN_PLAN:PASS"
