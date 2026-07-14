# What Works Today (Beginner Snapshot)

This page is a fast status snapshot for newcomers.

If you need deeper architectural details, use:

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`

## Workflows at a glance

| Workflow | Command shape | Current status | Notes |
| --- | --- | --- | --- |
| Upstream Haxe + `reflaxe.ocaml` | `haxe -lib reflaxe.ocaml ...` | Working | Compatibility-first baseline path. |
| `hxhx` + `reflaxe.ocaml` | `hxhx --ocaml ...` with `reflaxe.ocaml` validation/promotion docs | Experimental | Use for native compiler and hosting evidence, not as the default production route. |
| `hxhx` compat lane | `hxhx --ocaml-eval ...` / `hxhx --compat --js out.js ...` | Working | Delegates runtime compile to stage0 upstream `haxe`. |
| `hxhx` native OCaml lane | `hxhx --ocaml ...` | Working (scoped native lane) | Non-delegating runtime lane; use `HXHX_FORBID_STAGE0=1` for strict checks. |
| `hxhx` native JS lane | `hxhx --js out.js ...` | Working (scoped MVP) | Scope is intentionally bounded; see `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`. |
| Native backend plugin loading | `-D hxhx_backend_plugin_manifest=...` | Working | Uses `ocaml-dynlink` manifest kind (`.cmxs` / `.cma`). |
| Native macro module loading | `macro.loadNativeModule` / `macro.runNativeExpr` | Working (promoted-module rung) | ABI/version validation is enforced before registration. |

A useful milestone, but not the finish line: strict/full M7 run `29321576340`
proved that the bounded Macro, JavaScript, Neko, and plugin bundle works without
delegating to stage0 at commit `30a0b371`. It does **not** yet prove the complete
Full1 suite/target matrix or stage0-free bootstrap regeneration.

The two selected macro runtime modes also pass together in exact-commit run
`29334023225`. In plain language, the external mode can reuse one verified
macro-host program without secretly rebuilding it or falling back to upstream
Haxe. This still does **not** mean arbitrary projects can load all of their own
Haxe-written macros through that host; `haxe_ocaml-vhk47.3` owns that next step.

## Recommended starting points by intent

| I want to... | Start here |
| --- | --- |
| compile immediately with least risk | `docs/01-getting-started/QUICKSTART_COMPAT.md` |
| validate non-delegating runtime paths | `docs/01-getting-started/QUICKSTART_NATIVE.md` |
| compile to OCaml native executable with upstream `haxe` | `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md` |
| test `reflaxe.ocaml` through `hxhx` | `docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md` |
| promote a Reflaxe backend to native plugin artifact | `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md` |

## High-signal verification commands

```bash
npm run ci:guards
HXHX_FORCE_STAGE0=0 npm run test:hxhx-targets
npm run test:upstream:replacement-ready:strict
npm run test:hxhx:promotion-backend-smoke
```

For CI gate meaning and marker expectations:

- `docs/00-project/CI_GATES.md`

For current macro support boundaries (compat vs native matrix):

- `docs/02-user-guide/COMPILER_PLUGIN_SYSTEM.md`
