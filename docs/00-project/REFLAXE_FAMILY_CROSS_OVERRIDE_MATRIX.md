# Reflaxe Family `.cross.hx` / `_std` Matrix

This is the compact companion to:

- `docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`
- `docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_AUDIT.md`

Use this page when you need the answer quickly.
Use the guide when you need the reasoning.
Use the audit when you need the hardening implications.

## Family matrix

| Repo | Main override style | Uses `_std` | Uses `.cross.hx` | Early `src/haxe/*` ownership | Bootstrap activation shape | Current same-compilation coexistence risk | Recommended hardening priority |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `haxe.ocaml` | OCaml-owned `_std` layer plus tiny early exception set | Yes, primary | Yes, small/early-only set | Yes | narrow OCaml-specific gating | Medium to high | P2 |
| `haxe.elixir.codex` | broad `std/*.cross.hx` plus `_std` shims plus early exception | Yes | Yes, broad | Yes | broad on Haxe 4 because raw `Cross` currently counts | High | P1 |
| `haxe.go` | broad `.cross.hx` including `_std/*.cross.hx` | Yes | Yes, broad | No | narrow target-specific gating | Low to medium | P2 |
| `haxe.rust` | broad `std/**/*.cross.hx` | Minimal / not dominant | Yes, broad | No | narrow target-specific gating | Low to medium | P2 |

## What the columns mean

### Main override style

The repo's default answer to:

- "this stdlib module cannot be used as upstream ships it"

### Uses `_std`

Whether the repo keeps a target-owned shadow stdlib layer and how important that layer is to the target's design.

### Uses `.cross.hx`

Whether the repo relies on Haxe's `cross` platform file-selection model.

### Early `src/haxe/*` ownership

Whether the repo owns stdlib/core modules from `src/` early enough to affect macro/bootstrap typing before target `_std` injection has completed.

This is the most dangerous column for sibling collisions.

### Bootstrap activation shape

How aggressively the repo decides:

- "this is my target, inject my stdlib now"

Narrow activation is safer.
Broad activation is more likely to interfere with sibling targets.

### Same-compilation coexistence risk

Not "can these repos exist in the same company or CI pipeline".

It means:

- what happens if two sibling target libraries are active in the same Haxe compilation or future same-process backend/plugin activation path.

## Current overlap hotspots

These are the overlap surfaces that matter most right now.

| Module | Repos | Why it matters |
| --- | --- | --- |
| `haxe.Exception` | OCaml, Elixir, Rust | highest-risk family collision; OCaml/Elixir own early `src/` versions |
| `haxe.NativeStackTrace` | OCaml, Go | early OCaml ownership can beat Go's `std/` ownership |
| `StringTools` | Elixir, Go, Rust | broad std ownership overlap; lower risk than early `src/` collisions but still ambiguous in mixed activation |
| `DateTools` | Elixir, Go | broad std ownership overlap |
| `haxe.CallStack` | Go, Rust | broad std ownership overlap |
| `haxe.Constraints` | Go, Rust | broad std ownership overlap |

## Decision rule matrix

| Situation | Prefer `_std` | Prefer `.cross.hx` |
| --- | --- | --- |
| Normal target-private stdlib override | Yes | Usually no |
| Must be visible before target bootstrap injects `_std` | No | Yes |
| Repo intentionally uses `cross`-mode override selection as the main model | Maybe | Yes |
| Need a clear target-owned sync/provenance destination | Yes | Maybe |
| Want generic `cross`-mode selection rather than target-private classpath gating | No | Yes |

## Why `reflaxe.ocaml` keeps `String` in `_std`

Because `String` is a normal OCaml-owned override, not an early bootstrap exception.

That means:

- target-private activation is the right scope
- `_std/String.hx` is narrower than `String.cross.hx`
- and it fits this repo's stdlib provenance/sync model

## Why `reflaxe.ocaml` still keeps `haxe.Exception` in `src/*.cross.hx`

Because `_std` is too late for that module right now.

It must be visible early enough for bootstrap/macro typing to survive before `_std` injection has happened.

## Current operational truth

- I did **not** find a checked-in `haxe.ocaml` build that activates both `reflaxe.ocaml` and `reflaxe.elixir` in the same compilation by default.
- So the current family problem is a **latent structural hardening issue**, not a default reproduced failure in this repo.

That is why the current tasks are hardening tasks, not emergency regression tasks.

## Canonical local references

- guide: `docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`
- audit: `docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_AUDIT.md`
- matrix: `docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_MATRIX.md`
