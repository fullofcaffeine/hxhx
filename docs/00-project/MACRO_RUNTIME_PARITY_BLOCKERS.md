# Macro Runtime Parity Blockers

Last audited: 2026-03-05

This list tracks the explicit blockers for declaring `inproc` and `external-host` macro runtime modes parity-equivalent for production defaults.

Beginner summary:
- `external-host`: macros run in a separate `hxhx-macro-host` process.
- `inproc`: macros run inside `hxhx` directly.
- Goal: keep both green while we move default behavior to `inproc`.

## Open blockers

| Blocker ID | Gap | Why it matters | Tracking |
| --- | --- | --- | --- |
| MRP-B1 | In-process runtime currently supports the bring-up builtin subset and not full generated entrypoints. | Some macro patterns still require fallback behavior or remain unsupported in `inproc`. | `haxe.ocaml-bxlg.9` (epic), `haxe.ocaml-bxlg.9.3` |
| MRP-B2 | Macro API surface is still incomplete (`haxe.macro.Context` / `haxe.macro.Compiler` methods are partially implemented in bring-up layers). | Upstream macro compatibility claims are limited until API coverage expands. | `haxe.ocaml-bxlg.9` |
| MRP-B3 | Full upstream macro workloads and display checks are scheduled, not PR-required. | Regressions can land between scheduled runs and be detected later. | `haxe.ocaml-bxlg.9.2` |
| MRP-B4 | Default runtime mode is still `external-host` fallback-first policy. | We cannot claim in-process-first production behavior yet. | `haxe.ocaml-bxlg.9.3` |

## Exit criteria to clear this list

1. `inproc` runs the same macro surfaces as `external-host` for the scoped compatibility matrix.
2. Weekly parity workflow stays green across both modes and all selected suites.
3. Default runtime mode flips to `inproc` with documented fallback policy and rollback plan.
