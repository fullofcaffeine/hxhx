#!/usr/bin/env bash
set -euo pipefail

fixture_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$fixture_root/../../.." && pwd)"
server_helper="$repo_root/scripts/hxhx/haxe-server.sh"
run_root="$(mktemp -d "${TMPDIR:-/tmp}/native-custom-generator-contract.XXXXXX")"
server_state="$run_root/server-state"
server_port="${NATIVE_CUSTOM_GENERATOR_TEST_PORT:-$((28000 + ($$ % 8000)))}"
server_started=0

cleanup() {
	if [[ "$server_started" = "1" ]]; then
		HXHX_STATE_DIR="$server_state" \
			HXHX_HAXE_SERVER_PORT="$server_port" \
			HAXE_BIN=haxe \
			bash "$server_helper" stop >/dev/null 2>&1 || true
	fi
	find "$run_root" -depth -delete
}
trap cleanup EXIT

fail() {
	echo "native custom-generator contract fixture: $*" >&2
	exit 1
}

compile_contract() {
	local mode="$1"
	local public_root="$2"
	local trace_path="$3"
	local request_id="$4"
	local profile="$5"
	local fault="$6"
	local extra="$7"
	local compiler_output="$run_root/compiler-$request_id.js"
	local command=(haxe)
	if [[ "$mode" = "server" ]]; then
		command+=(--connect "$server_port")
	fi
	command+=(
		build.hxml
		-D "contract_trace=$trace_path"
		-D "contract_public_root=$public_root"
		-D "contract_request=$request_id"
		-D "contract_profile=$profile"
		-D "contract_fault=$fault"
		-js "$compiler_output"
	)
	if [[ "$extra" = "extra" ]]; then
		command+=(-D contract_extra)
	fi
	(
		cd "$fixture_root"
		"${command[@]}"
	)
}

assert_trace() {
	local trace_path="$1"
	shift
	local expected="$run_root/expected-$(basename "$trace_path")"
	printf '%s\n' "$@" >"$expected"
	diff -u "$expected" "$trace_path"
}

assert_clean_transaction_state() {
	local public_root="$1"
	if find "$(dirname "$public_root")" -maxdepth 1 \
		\( -name "$(basename "$public_root").candidate-*" -o -name "$(basename "$public_root").backup-*" \) \
		-print -quit | grep -q .; then
		fail "private candidate or backup state survived a request"
	fi
}

snapshot_public_root() {
	local public_root="$1"
	local snapshot_root="$2"
	rm -rf "$snapshot_root"
	cp -R "$public_root" "$snapshot_root"
}

assert_public_root_unchanged() {
	local public_root="$1"
	local snapshot_root="$2"
	diff -ru "$snapshot_root" "$public_root"
}

start_server() {
	if haxe --connect "$server_port" --version >/dev/null 2>&1; then
		fail "chosen compiler-server port $server_port is already in use"
	fi
	HXHX_STATE_DIR="$server_state" \
		HXHX_HAXE_SERVER_PORT="$server_port" \
		HAXE_BIN=haxe \
		bash "$server_helper" start >/dev/null
	server_started=1
}

if [[ "$(haxe --version)" != "4.3.7" ]]; then
	fail "expected upstream Haxe 4.3.7"
fi

clean_root="$run_root/clean-public"
clean_trace="$run_root/clean.trace"
compile_contract clean "$clean_root" "$clean_trace" clean typescript none none
assert_trace "$clean_trace" after-typing on-generate generator-prepare host-publish after-generate close

output_path="$clean_root/output.txt"
grep -Fqx 'contract=custom-generator-host-v2' "$output_path"
grep -Fqx 'profile=typescript' "$output_path"
grep -Fqx 'value=7' "$output_path"
grep -Fqx 'feature-present-before-add=false' "$output_path"
grep -Fqx 'feature-added=null' "$output_path"
grep -Fqx 'feature-present=true' "$output_path"
grep -Eq '^type-accessor-calls=[1-9][0-9]*$' "$output_path"
grep -Fq 'class:contract.ContractBox:parameters=T:parent=contract.ContractBase<contract.ContractBox.T>:interfaces=contract.ContractReadable<contract.ContractBox.T>' "$output_path"
grep -Fq ':format-overloads=1:' "$output_path"
grep -Fq ':envelope=envelope:type=contract.ContractEnvelope<contract.ContractBox.T>:' "$output_path"
grep -Fq ':unused-before-dce=true:' "$output_path"
grep -Fq 'interface:contract.ContractReadable:parameters=T:' "$output_path"
grep -Fq 'typedef:contract.ContractEnvelope:parameters=T:fields=label:optional=true:type=Null<String>,value:optional=false:type=contract.ContractEnvelope.T:' "$output_path"
grep -Fq 'abstract:contract.ContractMode:enum=true:underlying=String:values=Ready=string(ready),Waiting=string(waiting):' "$output_path"
grep -Eq 'position=ContractBox\.hx:[0-9]+-[0-9]+' "$output_path"
grep -Fq 'post-dce-facts=class:contract.ContractBox:unused-after-dce=false' "$output_path"
assert_clean_transaction_state "$clean_root"

public_root="$run_root/warm-public"
adjacent_file="$run_root/user-owned.txt"
printf '%s\n' 'preserve me' >"$adjacent_file"
start_server

trace_success_a="$run_root/success-a.trace"
compile_contract server "$public_root" "$trace_success_a" success-a classic none extra
assert_trace "$trace_success_a" after-typing on-generate generator-prepare host-publish after-generate close
grep -Fqx 'profile=classic' "$public_root/output.txt"
[[ -f "$public_root/extra.txt" ]] || fail "first successful request did not publish its extra file"
snapshot_public_root "$public_root" "$run_root/snapshot-before-seal"

trace_before_seal="$run_root/before-seal.trace"
if compile_contract server "$public_root" "$trace_before_seal" before-seal typescript before-seal none >"$run_root/before-seal.log" 2>&1; then
	fail "the injected pre-seal failure unexpectedly succeeded"
fi
grep -Fq 'injected custom-generator failure before candidate seal' "$run_root/before-seal.log"
assert_trace "$trace_before_seal" after-typing on-generate generator-prepare abort-before-seal close
assert_public_root_unchanged "$public_root" "$run_root/snapshot-before-seal"
assert_clean_transaction_state "$public_root"

trace_recovery_a="$run_root/recovery-a.trace"
compile_contract server "$public_root" "$trace_recovery_a" recovery-a classic none none
assert_trace "$trace_recovery_a" after-typing on-generate generator-prepare host-publish after-generate close
[[ ! -e "$public_root/extra.txt" ]] || fail "complete publication retained a stale generator-owned file"
snapshot_public_root "$public_root" "$run_root/snapshot-before-raw"

trace_raw="$run_root/raw.trace"
if compile_contract server "$public_root" "$trace_raw" raw classic raw extra >"$run_root/raw.log" 2>&1; then
	fail "the injected raw generator failure unexpectedly succeeded"
fi
grep -Fq 'injected raw custom-generator failure' "$run_root/raw.log"
assert_trace "$trace_raw" after-typing on-generate generator-prepare abort-raw close
assert_public_root_unchanged "$public_root" "$run_root/snapshot-before-raw"
assert_clean_transaction_state "$public_root"

trace_recovery_b="$run_root/recovery-b.trace"
compile_contract server "$public_root" "$trace_recovery_b" recovery-b classic none extra
assert_trace "$trace_recovery_b" after-typing on-generate generator-prepare host-publish after-generate close
snapshot_public_root "$public_root" "$run_root/snapshot-before-publish"

trace_during_publish="$run_root/during-publish.trace"
if compile_contract server "$public_root" "$trace_during_publish" during-publish typescript during-publish none >"$run_root/during-publish.log" 2>&1; then
	fail "the injected publication failure unexpectedly succeeded"
fi
grep -Fq 'injected custom-generator publication failure' "$run_root/during-publish.log"
assert_trace "$trace_during_publish" after-typing on-generate generator-prepare host-publish-rollback close
assert_public_root_unchanged "$public_root" "$run_root/snapshot-before-publish"
assert_clean_transaction_state "$public_root"

trace_final="$run_root/final.trace"
compile_contract server "$public_root" "$trace_final" final typescript none none
assert_trace "$trace_final" after-typing on-generate generator-prepare host-publish after-generate close
diff -ru "$clean_root" "$public_root"
grep -Fqx 'preserve me' "$adjacent_file"
assert_clean_transaction_state "$public_root"

printf '%s\n' 'NATIVE_CUSTOM_GENERATOR_CONTRACT_FIXTURE:PASS'
