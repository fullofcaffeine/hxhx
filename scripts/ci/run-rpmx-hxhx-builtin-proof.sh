#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MSG'
rpmx hxhx builtin proof: blocked.

The current tree does not yet have a runnable proof that builds the external
reflaxe.elixir compiler through a native hxhx built-in reflaxe.ocaml target
path. The official external native evidence lane is currently the hxhx plugin
host-adapter pilot:

  npm run test:rpmx:hxhx-plugin

Do not treat this blocked result as RPMX_HXHX_BUILTIN:PASS.
MSG

echo "RPMX_HXHX_BUILTIN:BLOCKED"
exit 4
