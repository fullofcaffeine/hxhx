#!/usr/bin/env bash
set -euo pipefail

# Hash the caller's ordered, newline-delimited file list in bounded batches.
# Keep the installed tool's digest token, including its filename-escape prefix.
# The caller owns the input inventory and hashes this manifest only on success.
ROOT="$1"
export LC_ALL=C
if command -v sha256sum >/dev/null 2>&1; then
	hash_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
	hash_command=(shasum -a 256)
else
	echo "Missing sha256 hash tool (need sha256sum or shasum)." >&2
	exit 1
fi

files=()
count=0
bytes=0
digest_pattern='^\\?[[:xdigit:]]{64}$'

# Validate the whole checksum response before emitting this batch. A missing
# file, failed tool, or truncated response must not identify reusable output.
flush_batch() {
	local output digest rest index=0 file rel
	local -a digests=()
	output="$("${hash_command[@]}" "${files[@]}")" || return 1
	while IFS=$' \t' read -r digest rest; do
		if [ "$index" -ge "$count" ] || [[ ! "$digest" =~ $digest_pattern ]]; then
			echo "Invalid bootstrap checksum output." >&2
			return 1
		fi
		digests+=("$digest")
		index=$((index + 1))
	done <<<"$output"
	if [ "$index" -ne "$count" ]; then
		echo "Incomplete bootstrap checksum output." >&2
		return 1
	fi
	for ((index = 0; index < count; index++)); do
		file="${files[$index]}"
		rel="${file#$ROOT/}"
		echo "file=$rel:${digests[$index]}"
	done
	files=()
	count=0
	bytes=0
}

while IFS= read -r file; do
	# Count bytes in the C locale. Stay well below supported hosts' argv limits.
	if [ "$count" -gt 0 ] && { [ "$count" -ge 128 ] || [ "$((bytes + ${#file} + 1))" -gt 16384 ]; }; then
		flush_batch
	fi
	files+=("$file")
	count=$((count + 1))
	bytes=$((bytes + ${#file} + 1))
done
if [ "$count" -gt 0 ]; then
	flush_batch
fi
