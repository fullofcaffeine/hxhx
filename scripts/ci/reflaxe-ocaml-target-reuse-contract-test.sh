#!/usr/bin/env bash
set -euo pipefail

# Proves the exact-source-reuse contract, its bounded in-memory catalog, and the
# real miss-to-hit compiler path. "Exact source reuse" means that an unchanged
# request may replay a previously validated generated OCaml tree; any changed or
# uncertain request must still run the one ordinary target compiler.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_SOURCE="$ROOT/test/reflaxe_ocaml_target_reuse/src"
CATALOG_SOURCE="$ROOT/test/reflaxe_target_reuse_catalog/src"

# Qualification originally generated a second disposable OCaml tree and wrote
# an observation-only report. Those mechanisms must stay deleted now that the
# real cache path is qualified, or the repository would again contain two
# generation paths that readers could mistake for product behavior.
for removed_path in \
	"$ROOT/packages/reflaxe.ocaml/src/reflaxe/ocaml/reuse/OcamlSourceBundleShadowReplay.hx" \
	"$ROOT/packages/reflaxe.ocaml/src/reflaxe/ocaml/reuse/OcamlTargetReuseReportWriter.hx" \
	"$ROOT/test/reflaxe_ocaml_target_reuse/src/TargetReuseReportFixture.hx"; do
	if [[ -e "$removed_path" ]]; then
		echo "reflaxe.ocaml target reuse hard cut: removed migration file returned: $removed_path" >&2
		exit 1
	fi
done
if grep -R -F 'reflaxe_ocaml_target_reuse_report' "$ROOT/packages/reflaxe.ocaml/src" >/dev/null 2>&1; then
	echo "reflaxe.ocaml target reuse hard cut: observation-only report define returned to production source" >&2
	exit 1
fi
echo "REFLAXE_OCAML_TARGET_REUSE_HARD_CUT:PASS"

cd "$ROOT"
haxe \
	-cp "$CATALOG_SOURCE" \
	-lib reflaxe \
	-D reflaxe_runtime \
	--run TargetReuseCatalogFixture

haxe \
	-cp packages/reflaxe.ocaml/src \
	-cp "$PROBE_SOURCE" \
	-lib reflaxe \
	-D reflaxe_runtime \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run TargetReuseContractFixture

haxe \
	-cp packages/reflaxe.ocaml/src \
	-cp "$PROBE_SOURCE" \
	-lib reflaxe \
	-D reflaxe_runtime \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run TargetSourceBundleCandidateFixture

echo "REFLAXE_OCAML_TARGET_REUSE_PROBE:PASS"

bash scripts/ci/reflaxe-ocaml-target-reuse-realm-test.sh
bash scripts/ci/reflaxe-ocaml-target-reuse-exact-hit-test.sh
