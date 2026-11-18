# Choose Your Lane

Pick one lane based on your goal. If terms are unfamiliar, read `docs/01-getting-started/TERMS_YOU_MUST_KNOW.md` first.

## Decision table

| Goal | Lane | First command | Next doc |
| --- | --- | --- | --- |
| I want OCaml output or a native binary from my Haxe project | Upstream `haxe` + `reflaxe.ocaml` (the first product) | `haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output` | `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md` |
| I want to test `reflaxe.ocaml` through `hxhx` | `hxhx + reflaxe.ocaml` lane. Not usable yet: `--ocaml` rejects ordinary programs. | None today | `docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md` |
| I want `hxhx` to compile my program, even if some work still goes to upstream `haxe` | `hxhx` compat lane (`--ocaml-eval` or `--compat --js <file>`) | `"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml-eval -cp src -main Main` | `docs/01-getting-started/QUICKSTART_COMPAT.md` |
| I want `hxhx` to do all the work, with upstream `haxe` forbidden | `hxhx` native lane (`--js <file>`, or `--ocaml --hxhx-no-emit` to parse and type only) | `HXHX_FORBID_STAGE0=1 "$(bash scripts/hxhx/build-hxhx.sh \| tail -n 1)" --js out.js -cp src -main Main` | `docs/01-getting-started/QUICKSTART_NATIVE.md` |
| I want compiler parity/replacement-readiness confidence | Replacement-ready strict gate lane | `npm run test:upstream:replacement-ready:strict` | `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md` |
| I want to build/promote a backend plugin | Promotion lane (linked-provider + ocaml-dynlink plugin workflows) | `bash scripts/hxhx/plugin-init.sh --out-dir .tmp/promotion-demo --plugin-id demo.native.plugin --target-id js-native` | `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md` |
| I want to embed `hxhx` inside another app | Subprocess embedding lane | `npm run hxhx:example:embedding-subprocess` | `docs/02-user-guide/EMBEDDING.md` |

## Canonical lane terms

- **compat lane**: `--compat` passthrough and `--ocaml-eval` delegated OCaml macro lane.
- **native lane**: `--js <file>` and `--ocaml`. `hxhx` parses and types the program itself and does not call upstream `haxe`. `--js` generates JavaScript for a [declared scope](../02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md). `--ocaml` runs the shared `reflaxe.ocaml` target core, which does not compile ordinary programs yet.
- **linked-provider plugin**: manifest kind that points at a Haxe provider type.
- **ocaml-dynlink plugin**: native runtime-loaded `.cmxs`/`.cma` provider artifact.

CLI cutover reminder:

- `--target` is removed; use direct lane flags only.
- `--target-id` is still valid in plugin scaffold/build scripts (for provider IDs), not for compile lane selection.

Legacy alias:

- `Haxe-provider` (legacy term) means `linked-provider`.

## Related docs

- `docs/01-getting-started/START_HERE.md`
- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
