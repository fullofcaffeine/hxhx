#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('fs')

const lowering = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (lowering.structuralIteratorConsumerModel !== 'typed-structural-iterator-consumer-v1')
	throw new Error('the lowering report has no typed structural Iterator consumer model')

const consumers = lowering.calls?.filter(call => call.kind === 'structural-iterator-method') ?? []
if (consumers.length === 0)
	throw new Error('the fixture did not seal any structural Iterator consumers')

const operations = new Set(consumers.map(consumer => consumer.structuralIteratorTarget?.operation))
for (const operation of ['has-next', 'next']) {
	if (!operations.has(operation))
		throw new Error(`the fixture did not seal structural Iterator.${operation}`)
}

for (const consumer of consumers) {
	const target = consumer.structuralIteratorTarget
	if (!target
		|| target.runtimeModule !== 'HxIterator'
		|| target.runtimeFunction !== (target.operation === 'has-next' ? 'hasNext' : 'next')
		|| target.receiverCarrierTypeId !== 'HxIterator.t'
		|| consumer.evaluationSchedule?.map(step => step.kind).join(',') !== 'materialize-receiver,invoke-callee'
		|| consumer.pipelineRevision !== 'ocaml-function-plans-v69') {
		throw new Error(`structural Iterator consumer ${consumer.id} is not fully sealed`)
	}
	const requirements = lowering.runtimeRequirements.filter(requirement => requirement.decisionId === consumer.id)
	if (requirements.length !== 1
		|| requirements[0].id !== `${consumer.id}:runtime:haxe-iterator`
		|| requirements[0].rootModules?.join(',') !== 'HxIterator') {
		throw new Error(`structural Iterator consumer ${consumer.id} does not own its exact runtime requirement`)
	}
}

const methodValues = lowering.structuralFields?.filter(field => field.operation === 'capture-iterator-method') ?? []
if (methodValues.length !== 2 || lowering.structuralFieldCount !== methodValues.length)
	throw new Error('the fixture did not seal both Iterator methods used as function values')
const methodNames = new Set(methodValues.map(field => field.fieldName))
for (const methodName of ['hasNext', 'next']) {
	if (!methodNames.has(methodName))
		throw new Error(`the fixture did not seal the Iterator.${methodName} method value`)
}
for (const method of methodValues) {
	const target = method.iteratorTarget
	if (!target
		|| target.proofId !== 'structural-iterator-runtime-method-value-v1'
		|| target.runtimeModule !== 'HxIterator'
		|| target.runtimeFunction !== method.fieldName
		|| method.runtimeModule !== 'HxIterator'
		|| method.runtimeOperation !== method.fieldName
		|| method.evaluationSchedule?.join(',') !== 'materialize-receiver,capture-method'
		|| method.pipelineRevision !== 'ocaml-function-plans-v69') {
		throw new Error(`Iterator method value ${method.id} is not fully sealed`)
	}
	const requirements = lowering.runtimeRequirements.filter(requirement => requirement.decisionId === method.id)
	if (requirements.length !== 1
		|| requirements[0].id !== `${method.id}:runtime:haxe-iterator`
		|| requirements[0].semanticCapability !== 'haxe-iterator'
		|| requirements[0].rootModules?.join(',') !== 'HxIterator') {
		throw new Error(`Iterator method value ${method.id} does not own its exact runtime requirement`)
	}
}

const runtime = JSON.parse(fs.readFileSync('out/ocaml_runtime_requirement_report.json', 'utf8'))
if (runtime.authorityStatus !== 'partial')
	throw new Error('this bounded consumer slice must not claim complete runtime authority')
if (runtime.compilerObservedModulesWithoutRequirementRoots.includes('HxIterator'))
	throw new Error('HxIterator remains compiler-observed without a typed consumer requirement')

const generated = [
	fs.readFileSync('out/Main.ml', 'utf8'),
	fs.readFileSync('out/Lambda.ml', 'utf8')
].join('\n')
if (!generated.includes('HxIterator.hasNext') || !generated.includes('HxIterator.next'))
	throw new Error('generated OCaml did not exercise both structural Iterator runtime operations')
if (/HxIterator\.(hasNext|next) \(Obj\.magic __iterator_receiver/.test(generated))
	throw new Error('the sealed Iterator carrier still reaches its direct runtime call through Obj.magic')
NODE

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
inspection_report="$(mktemp)"
lowering_backup="$(mktemp)"
cp out/ocaml_lowering_report.json "$lowering_backup"
trap 'cp "$lowering_backup" out/ocaml_lowering_report.json; rm -f "$inspection_report" "$lowering_backup"' EXIT

inspect() {
	(
		cd "$repo_root"
		haxe -cp packages/reflaxe.ocaml/src \
			--macro 'nullSafety("reflaxe.ocaml")' \
			--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
			inspect --project "$fixture_root" --output out --require-lowering --json
	)
}

inspect >"$inspection_report"
node - "$inspection_report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const consumers = report.lowering?.calls?.filter(call => call.kind === 'structural-iterator-method') ?? []
const methodValues = report.lowering?.structuralFields?.filter(field => field.operation === 'capture-iterator-method') ?? []
if (report.schemaVersion !== 34
	|| !report.summary?.valid
	|| consumers.length === 0
	|| methodValues.length !== 2
	|| report.summary.structuralFieldCount !== methodValues.length) {
	throw new Error('reflaxe.ocaml inspection did not preserve the sealed structural Iterator calls and method values')
}
NODE

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls.find(item => item.kind === 'structural-iterator-method')
call.structuralIteratorTarget.runtimeFunction = 'corrupted_runtime_function'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a corrupted structural Iterator runtime target" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const method = report.structuralFields.find(item => item.operation === 'capture-iterator-method')
method.iteratorTarget.proofId = 'structural-iterator-runtime-call-v1'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted an Iterator method value with a direct-call proof" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls.find(item => item.kind === 'structural-iterator-method')
call.structuralIteratorTarget = null
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a structural Iterator call with no target" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const call = report.calls.find(item => item.kind === 'structural-iterator-method')
call.pipelineRevision = 'ocaml-function-plans-stale'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a stale structural Iterator call" >&2
	exit 1
fi
cp "$lowering_backup" out/ocaml_lowering_report.json

node <<'NODE'
const fs = require('fs')
const path = 'out/ocaml_lowering_report.json'
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const requirement = report.runtimeRequirements.find(item => item.id.endsWith(':runtime:haxe-iterator'))
requirement.rootModules = ['HxArray']
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE
if inspect >"$inspection_report" 2>/dev/null; then
	echo "reflaxe.ocaml inspection accepted a corrupted structural Iterator runtime requirement" >&2
	exit 1
fi

echo "STRUCTURAL_ITERATOR_TYPED_CONSUMER:PASS"
