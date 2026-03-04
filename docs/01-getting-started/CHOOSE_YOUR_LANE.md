# Choose Your Lane

Pick one lane based on your goal. If terms are unfamiliar, read `docs/01-getting-started/TERMS_YOU_MUST_KNOW.md` first.

## Decision table

| Goal | Lane | First command | Next doc |
| --- | --- | --- | --- |
| I want OCaml output in my project with upstream `haxe` behavior | Upstream `haxe` + `reflaxe.ocaml` | `haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output` | `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md` |
| I want native binaries now, even if some work still delegates | `hxhx` compat lane (`--ocaml-eval` or `--compat --js <file>`) | `"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml-eval -cp src -main Main` | `docs/01-getting-started/QUICKSTART_COMPAT.md` |
| I want strict non-delegating behavior checks | `hxhx` native lane (`--ocaml` / `--js <file>`) with stage0 forbidden | `HXHX_FORBID_STAGE0=1 "$(bash scripts/hxhx/build-hxhx.sh)" --ocaml --hxhx-no-emit -cp src -main Main` | `docs/01-getting-started/QUICKSTART_NATIVE.md` |
| I want compiler parity/replacement-readiness confidence | Replacement-ready strict gate lane | `npm run test:upstream:replacement-ready:strict` | `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md` |
| I want to build/promote a backend plugin | Promotion lane (linked-provider + ocaml-dynlink plugin workflows) | `bash scripts/hxhx/plugin-init.sh --out-dir .tmp/promotion-demo --plugin-id demo.native.plugin --target-id js-native` | `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md` |
| I want to embed `hxhx` inside another app | Subprocess embedding lane | `npm run hxhx:example:embedding-subprocess` | `docs/02-user-guide/EMBEDDING.md` |

## Canonical lane terms

- **compat lane**: `--compat` passthrough and `--ocaml-eval` delegated OCaml macro lane.
- **native lane**: `--ocaml` / `--js <file>`; linked Stage3 path.
- **linked-provider plugin**: manifest kind that points at a Haxe provider type.
- **ocaml-dynlink plugin**: native runtime-loaded `.cmxs`/`.cma` provider artifact.

Legacy alias:

- `Haxe-provider` (legacy term) means `linked-provider`.

## Related docs

- `docs/01-getting-started/START_HERE.md`
- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
