# `.cross.hx` vs `_std`: Beginner Guide

This document explains three ideas that are easy to blur together when you first read a Reflaxe target:

- Haxe's `cross` platform
- `.cross.hx` files
- `_std` directories

They are related, but they are not the same thing.

## The short version

- `cross` is an upstream Haxe compiler platform.
- `.cross.hx` is a file-selection mechanism keyed off that platform.
- `_std` is a target-owned shadow-stdlib layer selected by classpath injection.

All three can participate in target stdlib support, but they solve different parts of the problem.

## What `cross` means

`cross` is not a Reflaxe invention.

In upstream Haxe, `Cross` is a real platform enum. Haxe starts in `Cross`, switches to a concrete built-in backend when one is selected, and skips built-in code generation when the platform remains `Cross`.

For custom targets, that matters because Haxe 4 Reflaxe targets commonly compile in that generic `cross` mode first.

Practical translation:

- `js`, `cpp`, `hl`, `python`, `eval`, etc. are concrete built-in platforms.
- `cross` is the generic custom-target bucket.
- `cross` does not by itself mean `ocaml`, `elixir`, `go`, or `rust`.

That last point is the part people usually miss.

## What `.cross.hx` means

A file like `String.cross.hx` means:

- "this is a platform-specific version of `String`"
- "pick it when the compiler is running in `cross` mode"

That is Haxe's file-resolution behavior. The filename suffix is doing the work.

So `.cross.hx` is good when you want:

- selection by Haxe platform,
- a target override that should not leak into non-`cross` contexts,
- or early visibility before a target-specific bootstrap can finish reshaping the classpath.

## What `_std` means

`_std` is not a Haxe syntax feature.

It is the conventional "shadow stdlib" directory used by Haxe targets.

A file like `std/_std/String.hx` is just a normal `String.hx`, but it lives in a classpath that is inserted ahead of the mainstream stdlib.

So `_std` is good when you want:

- a target-owned replacement stdlib layer,
- explicit target gating,
- a clear place to keep synced/provenanced stdlib overrides,
- and a normal module layout once the target is active.

## Why they overlap

They overlap because both can solve the same business problem:

- "this target cannot use the mainstream stdlib module as-is"

But they solve it through different routing mechanisms:

- `.cross.hx` uses Haxe platform resolution.
- `_std` uses classpath precedence.

So the overlap is real, but the activation path is different.

## Why `reflaxe.ocaml` mostly prefers `_std`

`reflaxe.ocaml` uses `_std` as the normal OCaml-owned stdlib layer.

Examples:

- `packages/reflaxe.ocaml/std/_std/String.hx`
- `packages/reflaxe.ocaml/std/_std/Array.hx`
- `packages/reflaxe.ocaml/std/_std/Sys.hx`

That matches the current bootstrap model:

- `std/` is always added for the haxelib surface,
- `std/_std` is injected only for actual OCaml target builds.

So `_std/String.hx` means:

- this is the OCaml target's `String`,
- not a generic cross-target `String`,
- and it should only appear after OCaml-specific gating is active.

That is narrower and easier to reason about than a generic `String.cross.hx`.

## Why `reflaxe.ocaml` still uses a few `.cross.hx` files

Because `_std` is not available early enough for everything.

`reflaxe.ocaml` currently has a tiny set of early bootstrap-visible files under `src/haxe/`:

- `packages/reflaxe.ocaml/src/haxe/Exception.cross.hx`
- `packages/reflaxe.ocaml/src/haxe/NativeStackTrace.cross.hx`
- `packages/reflaxe.ocaml/src/haxe/ValueException.cross.hx`

Those exist for a different reason than `_std/String.hx`.

They are needed early, before bootstrap has injected `std/_std`.

So the current OCaml split is:

- normal target-owned stdlib override: `_std/*.hx`
- early bootstrap-safe exception set: `src/**/*.cross.hx`

That is why `String` is in `_std`, while `haxe.Exception` is in `src/*.cross.hx`.

## Why `String.cross.hx` would be too broad for OCaml

A file named `String.cross.hx` says:

- use this when the build is in generic `cross` mode

But `cross` is not the same thing as `ocaml`.

If you key a file only off `cross`, that file is a candidate for any custom-target build that reaches it, not just OCaml.

By contrast, `_std/String.hx` in `reflaxe.ocaml` says:

- use this only if the OCaml bootstrap explicitly adds the OCaml shadow stdlib layer

That is why `_std/String.hx` is the better fit here.

## A simple decision rule

Choose `_std/Foo.hx` when:

- `Foo` is a normal target-owned stdlib override,
- you can wait until target bootstrap injects `_std`,
- and the override should only appear for that target.

Choose `src/.../Foo.cross.hx` when:

- `Foo` must be visible before `_std` is injected,
- or early macro/bootstrap typing will fail without it,
- and you still want to keep the file gated to `cross` rather than making it a plain always-visible `.hx` file.

Choose `std/Foo.cross.hx` or `_std/Foo.cross.hx` when:

- your target intentionally uses `cross`-mode file selection as the main override strategy,
- and your bootstrap/classpath model is built around that.

## How sibling targets differ

Within the current family of repos, the pattern is not uniform.

`reflaxe.ocaml`
- `_std` is the main target-owned stdlib layer.
- `.cross.hx` is the small early-bootstrap exception set.

`reflaxe.elixir`
- uses many `std/*.cross.hx` files as normal target-conditional overrides,
- plus `std/_std/**` for Elixir-only shims,
- plus `src/haxe/Exception.cross.hx` as an early-visible override.

`reflaxe.go`
- uses `.cross.hx` broadly for portable and staged stdlib ownership,
- including `_std/*.cross.hx`,
- and currently has no early `src/haxe/*.cross.hx` set.

`reflaxe.rust`
- uses `std/**/*.cross.hx` as the main override model,
- and currently has no early `src/haxe/*.cross.hx` set.

So there is no single family-wide rule like ".cross.hx always means early bootstrap".

## When multiple target libraries are active together

This is where things get dangerous.

If two target libraries are loaded into the same Haxe `cross` compilation, `.cross.hx` can collide on module names.

The clearest current example is `haxe.Exception`:

- OCaml owns `src/haxe/Exception.cross.hx`
- Elixir owns `src/haxe/Exception.cross.hx`
- Rust owns `std/haxe/Exception.cross.hx`

Haxe resolves one module for `haxe.Exception`.

It does not merge them.

That means classpath order decides which file wins.

If the wrong one wins, the active target may see only a fallback `extern` surface instead of its real runtime-backed implementation.

## Is that happening by default today?

Not in the checked-in `haxe.ocaml` workflows I audited.

I did not find a checked-in build in this repo that activates both `reflaxe.ocaml` and `reflaxe.elixir` in the same compilation.

So this is currently a latent hardening risk, not a default reproduced failure.

That distinction matters:

- current default path: not broken by default
- same-compilation mixed-target path: unsafe today

## Why this matters anyway

The repo family is moving toward stronger native/plugin backend composition.

That makes same-process and same-workspace coexistence more important over time.

If we do not harden these ownership boundaries now, future backend/plugin activation can inherit brittle classpath-order behavior.

## What we audited across the family

Current high-level findings:

- All four repos already have staged pre-commit local-path guards that reject machine-local absolute paths.
- `reflaxe.ocaml` currently uses `.cross.hx` conservatively and mostly correctly for early bootstrap needs.
- `reflaxe.elixir` has the sharpest current activation risk because its Haxe 4 bootstrap treats generic `Cross` as enough to identify an Elixir build.
- `reflaxe.go` and `reflaxe.rust` are narrower because their bootstrap activation keys off target-specific defines instead of raw `Cross`.
- Mixed-target same-compilation hardening is still worth doing across the family even where current default activation is narrow.

## Local sibling references

If you are working in the multi-repo workspace, see also:

- `docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_AUDIT.md`
- `../haxe.elixir.codex/docs/05-architecture/CROSS_OVERRIDES_AND_MULTI_TARGET_HARDENING.md`
- `../haxe.go/docs/cross-overrides-and-hardening.md`
- `../haxe.rust/docs/cross-overrides-and-hardening.md`

These sibling-relative paths are intended for local workspace navigation and agent handoff. They are not part of a published single-site docs tree.
