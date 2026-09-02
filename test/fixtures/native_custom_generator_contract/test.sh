#!/usr/bin/env bash
set -euo pipefail

fixture_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_root="$(mktemp -d "${TMPDIR:-/tmp}/native-custom-generator-contract.XXXXXX")"
trap 'rm -rf "$run_root"' EXIT

output_path="$run_root/output.txt"
trace_path="$run_root/trace.txt"

cd "$fixture_root"
haxe build.hxml -D "contract_trace=$trace_path" -js "$output_path"

expected_trace="$run_root/expected-trace.txt"
printf '%s\n' \
  'after-typing' \
  'on-generate' \
  'generator-prepare' \
  'after-generate' >"$expected_trace"
diff -u "$expected_trace" "$trace_path"

grep -Fqx 'contract=custom-generator-host-v1' "$output_path"
grep -Fqx 'value=7' "$output_path"
grep -Fqx 'feature-added=null' "$output_path"
grep -Fqx 'feature-present=true' "$output_path"
grep -Eq '^type-accessor-calls=[1-9][0-9]*$' "$output_path"
grep -Fq 'contract.ContractBox' "$output_path"
grep -Fq 'contract.ContractEnvelope' "$output_path"
grep -Fq 'contract.ContractMode' "$output_path"
grep -Fq 'class:contract.ContractBox:parameters=1:interfaces=1:read=true:source=ContractBox.hx' "$output_path"
grep -Fq 'interface:contract.ContractReadable:parameters=1:interfaces=0:read=true:source=ContractBox.hx' "$output_path"
grep -Fq 'typedef:contract.ContractEnvelope:parameters=1:anonymous-fields=1:source=ContractBox.hx' "$output_path"
grep -Fq 'abstract:contract.ContractMode:enum=true:source=ContractBox.hx' "$output_path"

printf '%s\n' 'NATIVE_CUSTOM_GENERATOR_CONTRACT_FIXTURE:PASS'
