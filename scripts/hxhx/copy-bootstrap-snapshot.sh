#!/usr/bin/env bash
# Copy generator output into the committed bootstrap-snapshot shape.
#
# The generator output directory may also contain temporary build receipts and
# reports. Those files describe one local build; they are not compiler source
# and must not become part of the reusable snapshot.

set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <generated-output-dir> <bootstrap-snapshot-dir>" >&2
	exit 2
fi

source_dir="$1"
snapshot_dir="$2"

if [ ! -d "$source_dir" ]; then
	echo "Missing generated output directory: $source_dir" >&2
	exit 1
fi
if [ ! -d "$snapshot_dir" ]; then
	echo "Missing bootstrap snapshot directory: $snapshot_dir" >&2
	exit 1
fi

(cd "$source_dir" && tar \
	--exclude='_build' \
	--exclude='_gen_hx' \
	--exclude='ocaml_*_report.json' \
	--exclude='ocaml_artifact_manifest.json' \
	--exclude='ocaml_semantic_lifecycle_trace.json' \
	--exclude='hxhx-current-source.env' \
	-cf - .) | (cd "$snapshot_dir" && tar -xf -)
