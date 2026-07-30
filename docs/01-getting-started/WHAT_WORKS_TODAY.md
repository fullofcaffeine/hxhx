# What Works Today (Beginner Snapshot)

This page is a fast status snapshot for newcomers.

If you need deeper architectural details, use:

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`

## Workflows at a glance

| Workflow | Command shape | Current status | Notes |
| --- | --- | --- | --- |
| Upstream Haxe + `reflaxe.ocaml` | `haxe -lib reflaxe.ocaml ...` | Working | Compatibility-first baseline path. |
| `hxhx` + `reflaxe.ocaml` | `hxhx --ocaml ...` with `reflaxe.ocaml` validation/promotion docs | Experimental | The current target wrapper delegates to the separate Stage3 emitter, not standalone `reflaxe.ocaml`; use it for native compiler and hosting evidence, not as the default production route. |
| `hxhx` compat lane | `hxhx --ocaml-eval ...` / `hxhx --compat --js out.js ...` | Working | Delegates runtime compile to stage0 upstream `haxe`. |
| `hxhx` native OCaml lane | `hxhx --ocaml ...` | Working (scoped bootstrap lane) | Non-delegating runtime lane through Stage3 OCaml emission; use `HXHX_FORBID_STAGE0=1` for strict checks. This is not yet the standalone target hard cut. |
| `hxhx` native JS lane | `hxhx --js out.js ...` | Working (scoped MVP) | Scope is intentionally bounded; see `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`. |
| Native backend plugin loading | `-D hxhx_backend_plugin_manifest=...` | Working | Uses `ocaml-dynlink` manifest kind (`.cmxs` / `.cma`). |
| One native Reflaxe target core for stock Haxe and `hxhx` | Planned M22 semantic ABI | Deferred | Current stock-Haxe eval-host and `hxhx` artifacts are host-specific. M22 waits for Full1, the authentic target hard cut, and two-generation self-promotion. It requires one semantic core and contract; one combined `.cmxs` is a feasibility experiment, while exact generated host shells are allowed. |
| Native macro module loading | `macro.loadNativeModule` / `macro.runNativeExpr` | Working (promoted-module rung) | ABI/version validation is enforced before registration. |

A useful milestone, but not the finish line: strict/full M7 run `29321576340`
proved that the bounded Macro, JavaScript, Neko, and plugin bundle works without
delegating to stage0 at commit `30a0b371`. It does **not** yet prove the complete
Full1 suite/target matrix or stage0-free bootstrap regeneration.

“Stage0-forbidden” applies to the compiler-under-test after `hxhx` has been
built: the workload must fail instead of quietly delegating to the installed
upstream `haxe`. Stage0 may still be the starter compiler used to build the
first binary, and downstream tools such as Node, Neko, dune, or clang remain
normal parts of their target lanes.

The two selected macro runtime modes pass together in exact-commit run
`29334023225`. A newer exact-commit run, `29349360051`, also proves the first
project-defined Haxe macro path: `hxhx` generated a small authenticated plugin,
then loaded and ran that same macro through both the in-process and external
host modes without falling back to upstream Haxe. This is one no-argument macro
proof, not a promise that every existing project macro is supported yet.

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
