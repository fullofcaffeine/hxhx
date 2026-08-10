#!/usr/bin/env bash
set -euo pipefail

report_file="out/ocaml_lowering_report.json"
if [ ! -f "$report_file" ]; then
	echo "Missing generated lowering report: $report_file" >&2
	exit 1
fi

# This program starts with one direct Array<String> literal producer. Its two
# resize calls are also explicit typed consumers. Other compiler families must
# not claim Array<String> merely because they recognize the source type.
node - "$report_file" <<'NODE'
const fs = require('node:fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const sha256 = /^sha256:[0-9a-f]{64}$/

const descriptors = report.representedArrays.filter(entry => entry.arraySemanticTypeId === 'Array<String>')
const producers = report.arrayLiteralProducers.filter(entry => entry.arraySemanticTypeId === 'Array<String>')
const calls = report.calls.filter(entry => entry.standardArrayTarget?.receiverSemanticTypeId === 'Array<String>')
if (descriptors.length !== 1 || producers.length !== 1) {
	throw new Error(`expected one literal-owned Array<String> descriptor and producer, got ${descriptors.length} descriptors and ${producers.length} producers`)
}
const descriptor = descriptors[0]
const producer = producers[0]
if (descriptor.id !== 'represented-array:Array<String>'
	|| descriptor.elementSemanticTypeId !== 'String'
	|| descriptor.elementCarrierTypeId !== 'string'
	|| descriptor.elementRepresentationId !== 'representation:String:array-element'
	|| !sha256.test(descriptor.elementRepresentationRevision)
	|| descriptor.arrayCarrierTypeId !== 'string HxArray.t'
	|| !sha256.test(descriptor.revision)
	|| producer.functionId.indexOf('|function|main|') < 0
	|| producer.arrayCarrierTypeId !== descriptor.arrayCarrierTypeId
	|| producer.arrayDescriptorId !== descriptor.id
	|| producer.arrayDescriptorRevision !== descriptor.revision
	|| producer.elementRepresentationId !== descriptor.elementRepresentationId
	|| producer.elementRepresentationRevision !== descriptor.elementRepresentationRevision
	|| producer.proofId !== 'direct-array-string-literal-construction-v1'
	|| producer.elements.length !== 2
	|| producer.runtimeRequirementIds?.length !== 1
	|| producer.runtimeRequirementIds[0] !== `${producer.id}:runtime:haxe-array-literal-construction`
	|| producer.runtimeUseOccurrences?.map(use => use.exactSymbol).join(',') !== 'HxArray.create,HxArray.push,HxArray.push'
	|| producer.runtimeUseOccurrences.map(use => use.order).join(',') !== '0,2,4'
	|| producer.evaluationSchedule.map(step => step.kind).join(',')
		!== 'create-array,evaluate-element,store-element,evaluate-element,store-element,result-array') {
	throw new Error('the direct Array<String> literal did not retain its exact descriptor, element carrier, and evaluation schedule')
}
const requirement = report.runtimeRequirements.find(entry => entry.id === producer.runtimeRequirementIds[0])
if (requirement?.sourceId !== producer.id
	|| requirement.decisionId !== producer.id
	|| requirement.semanticCapability !== 'haxe-array-literal-construction'
	|| requirement.implementationFeature !== 'haxe-array-literal-construction-v1'
	|| requirement.subject?.id !== 'Array<String>'
	|| requirement.rootModules?.join(',') !== 'HxArray') {
	throw new Error('the direct Array<String> literal did not publish its exact HxArray construction requirement')
}
if (calls.length !== 2 || calls.some(call => call.kind !== 'standard-array-method'
	|| call.sourceFieldName !== 'resize'
	|| call.standardArrayTarget.operation !== 'resize'
	|| call.standardArrayTarget.runtimeModule !== 'HxArray'
	|| call.standardArrayTarget.runtimeFunction !== 'resize'
	|| call.standardArrayTarget.elementSemanticTypeId !== 'String'
	|| call.standardArrayTarget.resultKind !== 'effect-only-void'
	|| call.evaluationSchedule.map(step => step.kind).join(',') !== 'materialize-receiver,materialize-argument,invoke-callee')) {
	throw new Error('the two Array<String>.resize calls did not retain their exact typed targets and receiver-first schedules')
}
for (const [name, value] of Object.entries(report)) {
	if (Array.isArray(value)
		&& name !== 'representations'
		&& name !== 'representedArrays'
		&& name !== 'arrayLiteralProducers'
		&& name !== 'calls'
		&& name !== 'runtimeRequirements'
		&& value.some(entry => JSON.stringify(entry).includes('Array<String>'))) {
		throw new Error(`Array<String> escaped its admitted producer, call, and runtime boundaries through report inventory ${name}`)
	}
}
NODE

bash ../../../../scripts/reflaxe-ocaml/run-string-array-element-oracle.sh

echo "STRING_ARRAY_ELEMENT_RUNTIME_BOUNDARY:PASS"
