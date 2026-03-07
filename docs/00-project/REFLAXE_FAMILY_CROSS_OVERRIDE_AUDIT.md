# Reflaxe Family `.cross.hx` / `_std` Audit

This document records the current cross-repo audit for:

- this repo (`haxe.ocaml`)
- sibling `../haxe.elixir.codex`
- sibling `../haxe.go`
- sibling `../haxe.rust`

It is written as a hardening reference, not as a release contract.

Companion docs:

- beginner guide: `docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`
- quick matrix: `docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_MATRIX.md`

## Scope

Questions audited:

1. What does each repo use `.cross.hx` for?
2. What does each repo use `_std` for?
3. Does the repo have early `src/haxe/*` ownership that can collide with siblings?
4. Would multiple target libraries in one compilation be safe today?
5. Does the repo already have pre-commit protection against machine-local absolute paths?

## Family summary

| Repo | Main std override style | Early `src/haxe/*` ownership | Mixed-target same-compile risk | Local-path pre-commit guard |
| --- | --- | --- | --- | --- |
| `haxe.ocaml` | `_std/*.hx` plus tiny early `.cross.hx` set | Yes | Medium to high | Yes |
| `haxe.elixir.codex` | many `std/*.cross.hx`, plus `_std`, plus early `src/haxe/*` | Yes | High | Yes |
| `haxe.go` | many `.cross.hx`, including `_std/*.cross.hx` | No | Low to medium | Yes |
| `haxe.rust` | many `std/**/*.cross.hx` | No | Low to medium | Yes |

## Repo-by-repo findings

### `haxe.ocaml`

Current model:

- normal OCaml stdlib ownership lives in `packages/reflaxe.ocaml/std/_std/**`
- bootstrap adds `std/` always and `std/_std` only for actual OCaml builds
- only three `.cross.hx` files exist, all under `src/haxe/`

Interpretation:

- `_std` is the primary target-owned stdlib layer
- `.cross.hx` is currently the early-bootstrap exception lane

Hardening concern:

- `src/haxe/Exception.cross.hx`
- `src/haxe/NativeStackTrace.cross.hx`
- `src/haxe/ValueException.cross.hx`

can still shadow sibling target ownership if multiple target libraries are loaded into one `cross` compilation.

### `haxe.elixir.codex`

Current model:

- many `std/*.cross.hx` files are normal target-conditional overrides
- `std/_std/**` holds Elixir-only shims
- `src/haxe/Exception.cross.hx` is early-visible
- Haxe 4 bootstrap currently treats generic `Cross` as enough to identify an Elixir build

Interpretation:

- this repo intentionally leans more heavily on `.cross.hx` than OCaml does
- the broad Haxe 4 bootstrap gate is the sharpest current coexistence risk in the family

Hardening concern:

- same-compilation coexistence with sibling targets is unsafe today if classpaths overlap
- the `Cross => Elixir build` heuristic is too broad for family coexistence

### `haxe.go`

Current model:

- `.cross.hx` is used broadly for portable/staged ownership
- `_std/*.cross.hx` is also used
- no early `src/haxe/*.cross.hx` set was found
- bootstrap gates on target-specific detection rather than generic `Cross`

Interpretation:

- this repo is safer than Elixir for mixed activation because bootstrap is narrower
- but it still shares module names with siblings under `std/**/*.cross.hx`

Hardening concern:

- same-compilation coexistence can still become ambiguous if conflicting sibling classpaths are present
- especially for modules also owned early by siblings like `haxe.NativeStackTrace`

### `haxe.rust`

Current model:

- `std/**/*.cross.hx` is the main override model
- no early `src/haxe/*.cross.hx` set was found
- bootstrap gates on target-specific Rust detection rather than generic `Cross`

Interpretation:

- activation is narrower than Elixir's current Haxe 4 path
- but module-name overlaps with siblings still exist

Hardening concern:

- `haxe.Exception` is owned by Rust under `std/`, while OCaml and Elixir currently own early `src/haxe/Exception.cross.hx`
- if a sibling early file wins resolution first, Rust can lose the real implementation it expected

## Concrete overlap inventory

The most important cross-repo module overlaps found in this audit were:

- `haxe.Exception`
  - OCaml `src/`
  - Elixir `src/`
  - Rust `std/`
- `haxe.NativeStackTrace`
  - OCaml `src/`
  - Go `std/`
- `StringTools`
  - Elixir `std/`
  - Go `std/`
  - Rust `std/`
- `DateTools`
  - Elixir `std/`
  - Go `std/`
- `haxe.CallStack`
  - Go `std/`
  - Rust `std/`

Not every overlap is equally dangerous.

The highest-risk overlaps are the ones involving early `src/haxe/*` ownership, because those files can win resolution before a target-private `_std` layer or a narrower bootstrap gate gets a chance to shape the build.

## Current default-risk statement

Important distinction:

- I did **not** find a checked-in `haxe.ocaml` build that loads both `reflaxe.ocaml` and `reflaxe.elixir` in the same compilation.
- So this audit is documenting a real structural risk, not claiming a currently reproduced default failure in this repo.

That means the correct planning stance is:

- document now
- harden before multi-backend same-compilation activation becomes normal
- do not pretend a default green path is already broken if it is not

## Pre-commit absolute-path protection

All four repos already have staged local-path leak protection in pre-commit.

Summary:

- `haxe.ocaml`: `scripts/hooks/pre-commit` runs `scripts/ci/local-path-check.js --staged`
- `haxe.elixir.codex`: `scripts/hooks/pre-commit` runs `scripts/lint/local_path_guard_staged.sh`
- `haxe.go`: `scripts/hooks/pre-commit` runs `scripts/lint/local_path_guard_staged.sh`
- `haxe.rust`: `scripts/hooks/pre-commit` runs `scripts/lint/local_path_guard_staged.sh`

So the path-leak prevention baseline already exists. The remaining work is mostly around target activation and module ownership hardening, not hook absence.

## Recommended hardening direction

### High priority

- Narrow broad bootstrap activation that keys off raw `Cross` instead of target identity.
- Add explicit mixed-target detection/fail-fast behavior when multiple sibling target libraries become active in one compilation.
- Document which modules are early-ownership exceptions and why.

### Medium priority

- Add a regression or smoke test for mixed sibling activation where practical.
- Keep `_std` / `.cross.hx` ownership rules written down per repo so future contributors do not move files casually.

### Low priority

- Unify family wording and cross-references so the same concepts are described consistently.

## Local sibling references

Workspace-local companion docs:

- `docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`
- `../haxe.elixir.codex/docs/05-architecture/CROSS_OVERRIDES_AND_MULTI_TARGET_HARDENING.md`
- `../haxe.go/docs/cross-overrides-and-hardening.md`
- `../haxe.rust/docs/cross-overrides-and-hardening.md`
