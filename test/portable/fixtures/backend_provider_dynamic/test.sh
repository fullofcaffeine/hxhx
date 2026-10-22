#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -cp ../../../../packages/hxhx/src -cp ../../../../packages/hxhx-core/src -cp ../../../../packages/reflaxe.ocaml/src -D hxhx_stage0_ocaml_only -dce full --macro "keep('backend.ITargetBackendProvider')" -main ProviderMain --interp)
echo 'BACKEND_PROVIDER_DYNAMIC:PASS'
