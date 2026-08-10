#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated String source or lowering report" >&2
	exit 1
fi

if ! grep -Eq '^type stringstate_t = .*mutable omitted : string.*mutable empty : string' "$source_file"; then
	echo "Exact String instance fields did not use the sealed string carrier" >&2
	exit 1
fi
if ! grep -Eq 'omitted = HxString.hx_null_string; empty = ""; explicitNull = HxString.hx_null_string.*: stringstate_t' "$source_file"; then
	echo "Omitted and empty instance Strings are not distinct in generated storage" >&2
	exit 1
fi
if ! grep -Eq 'let omitted = ref \(HxString.hx_null_string : string\)' "$source_file"; then
	echo "The omitted static String did not consume its sealed null default" >&2
	exit 1
fi
if grep -Eq '(omitted|local) = \"\"' "$source_file"; then
	echo "An omitted admitted String still defaulted to the empty string" >&2
	exit 1
fi
if grep -Eq 'Obj.magic.*HxRuntime.hx_null' "$source_file"; then
	echo "An admitted exact String occurrence emitted a fresh unsafe null cast instead of the runtime-owned sentinel" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('node:fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))

function fail(message) {
	console.error(`String representation report check failed: ${message}`)
	process.exit(1)
}

if (report.schemaVersion !== 76
	|| report.representationScope !== 'exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15'
	|| report.callModel !== 'typed-ocaml-directional-call-boundary-v25') {
	fail('unexpected lowering report, representation, or call-model version')
}

const strings = report.representations.filter(entry => entry.semanticTypeId === 'String')
for (const domain of ['internal-value', 'mutable-local-storage', 'instance-field', 'static-field']) {
	const decision = strings.find(entry => entry.domain === domain)
	if (!decision
		|| decision.carrierTypeId !== 'string'
		|| decision.nullPolicy !== 'runtime-sentinel'
		|| decision.boxingPolicy !== 'nullable-string-carrier'
		|| decision.implicitDefaultPolicy !== 'runtime-null-sentinel'
		|| decision.proof?.id !== 'nullable-string-runtime-sentinel-carrier-v1') {
		fail(`missing complete exact String decision for ${domain}`)
	}
}

const stringRequirements = report.runtimeRequirements.filter(entry =>
	entry.semanticCapability === 'haxe-string-null-sentinel')
if (stringRequirements.length !== strings.length)
	fail('every exact String representation must retain its runtime requirement')
for (const decision of strings) {
	const requirement = stringRequirements.find(entry =>
		entry.id === `${decision.id}:runtime:haxe-string-null-sentinel`)
	if (!requirement
		|| requirement.sourceKind !== 'representation-decision'
		|| requirement.sourceId !== `${decision.id}@${decision.revision}`
		|| requirement.cause !== 'representation-decision'
		|| requirement.decisionId !== decision.id
		|| requirement.subject?.kind !== 'haxe-type'
		|| requirement.subject?.id !== 'String'
		|| requirement.rootModules?.join(',') !== 'HxString') {
		fail(`missing exact HxString dependency for ${decision.id}`)
	}
}

const staticString = report.staticStorage.find(entry =>
	entry.semanticTypeId === 'String'
	&& entry.fieldName === 'omitted'
	&& entry.representationId === 'representation:String:static-field')
if (!staticString)
	fail('omitted static String did not retain its representation identity')

const instanceAssignment = report.plans.find(entry =>
	entry.nodeKind === 'simple-assignment'
	&& entry.semanticTypeId === 'String'
	&& entry.carrierTypeId === 'string'
	&& entry.place?.fieldName === 'omitted'
	&& entry.place?.representationId === 'representation:String:instance-field')
if (!instanceAssignment
	|| instanceAssignment.conversion !== 'identity') {
	fail('instance String assignment did not consume the sealed direct carrier decision')
}

const stringCalls = report.calls.filter(call =>
	call.arguments.some(argument => argument.outputSemanticTypeId === 'String')
	|| call.result.outputSemanticTypeId === 'String')
if (stringCalls.length === 0)
	fail('no exact String call boundary was admitted')
for (const call of stringCalls) {
	for (const value of call.arguments.concat([call.result])) {
		if (value.inputSemanticTypeId === 'String' || value.outputSemanticTypeId === 'String') {
			if (value.inputCarrierTypeId !== 'string'
				|| value.outputCarrierTypeId !== 'string'
				|| value.conversion !== 'identity') {
				fail(`call ${call.id} did not preserve its exact String carrier`)
			}
		}
	}
}
NODE

first_report_sha="$(shasum -a 256 "$report_file" | awk '{print $1}')"
haxe build.hxml
second_report_sha="$(shasum -a 256 "$report_file" | awk '{print $1}')"
if [ "$first_report_sha" != "$second_report_sha" ]; then
	echo "Exact String lowering report changed across identical compilations" >&2
	exit 1
fi

if [ "$(haxe --version)" != "4.3.7" ]; then
	echo "This oracle fixture requires upstream Haxe 4.3.7" >&2
	exit 1
fi
oracle_dir="$(mktemp -d "${TMPDIR:-/tmp}/string-null-storage-oracle.XXXXXX")"
trap 'rm -rf "$oracle_dir"' EXIT
haxe -cp src -main Main -js "$oracle_dir/oracle.js"
node "$oracle_dir/oracle.js" >"$oracle_dir/oracle.js.stdout"
haxe -cp src -main Main -neko "$oracle_dir/oracle.n"
neko "$oracle_dir/oracle.n" >"$oracle_dir/oracle.neko.stdout"
diff -u expected.stdout "$oracle_dir/oracle.js.stdout"
diff -u expected.stdout "$oracle_dir/oracle.neko.stdout"

echo "STRING_NULL_STORAGE_ORACLE_REPORT_AND_SOURCE_SHAPE:PASS"
