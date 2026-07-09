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

## Are `.cross.hx` and `_std` equivalent?

They can be equivalent in outcome, but they are not equivalent mechanisms.

Both can make Haxe type `String`, `Array`, `Std`, `Sys`, or another stdlib module using your target's implementation instead of upstream Haxe's default implementation.

That is the equivalent part:

- `String.cross.hx` can replace `String` for a `cross` build
- `_std/String.hx` can replace `String` when `_std` is inserted before the default stdlib

But the switch that activates the replacement is different:

| Shape | Activation switch | Scope |
| --- | --- | --- |
| `String.cross.hx` | Haxe's platform file resolver chooses the `.cross.hx` file while the compiler platform is `cross`. | Any custom-target build that sees that classpath can be affected. |
| `_std/String.hx` | A target bootstrap or compiler setup adds the `_std` directory before the default stdlib. | Only builds where that classpath injection happens are affected. |

So the useful mental model is:

- `.cross.hx` says "use me for the generic custom-target platform"
- `_std` says "use me when this target deliberately adds my shadow stdlib"

For a single target in isolation, the two choices can feel the same because both make the target's `String` win.

For multiple targets, packaging, and bootstrap timing, they are different enough that choosing the wrong one can create bugs.

## When to use each

Use `_std/*.hx` when you want the normal, readable target-owned stdlib source tree:

- the override is not needed until the target is known
- the target has a bootstrap/init step that can add `_std`
- you want the file to be target-private rather than generic-`cross`
- you want the repo layout to resemble upstream Haxe target stdlibs like `std/js/_std` or `std/python/_std`

Use direct `.cross.hx` when classpath timing or package shape requires it:

- in a staged-bootstrap target, the module must be visible before target bootstrap can add `_std`
- the haxelib package is flattened and the override lives in the initial classpath
- the target intentionally treats Haxe's `cross` platform as its stdlib selection gate
- you need a file to be hidden from non-`cross` builds but available without extra classpath injection

Use a packaging conversion from `_std/*.hx` to `.cross.hx` when both are true:

- source development is cleaner with `_std/*.hx`
- the distributable haxelib package needs those files flattened into one classpath

That last case is what Reflaxe's own build script supports for newer/template-style targets.

The local reference Reflaxe compilers mostly show the second and third cases, not the first one:

- `reflaxe_go` keeps many `.cross.hx` files directly in `src/`, including `src/haxe/*.cross.hx`, because those overrides already live on the initial haxelib classpath. It is not doing a later `_std` injection step.
- `reflaxe.CPP`, `reflaxe.GDScript`, and `reflaxe.lua` keep source overrides in `_std/*.hx`; their compiler init files do not inject `_std` with `Compiler.addClassPath`.
- During development, Reflaxe's `test` command passes each target's `stdPaths` to Haxe up front, before typing the target program.
- Reflaxe's own package build can turn those source `_std/*.hx` files into package `.cross.hx` files when flattening the haxelib.

So "needed before bootstrap can add `_std`" is a real reason to use direct `.cross.hx`, but it is not the main pattern shown by the reference sample compilers in `haxe.compilerdev.reference`. It is the reason for `reflaxe.ocaml`'s small early `src/haxe/` exception set.

## Reflaxe source layout vs package layout

There is one more Reflaxe-specific wrinkle: a target's source checkout and its published haxelib package do not have to look the same.

The Reflaxe framework template in `../haxe.compilerdev.reference/reflaxe/newproject` uses this source layout:

- compiler code in `src/`
- target API files in `std/`
- target stdlib overrides in `std/LANG/_std/*.hx`
- `haxelib.json` with `reflaxe.stdPaths`, for example `["std", "std/LANG/_std"]`

During local development, Reflaxe's own `test` command adds those paths directly. In that mode, the target can work from normal `_std/*.hx` files.

During `haxelib run reflaxe build`, Reflaxe has to produce a package shape that haxelib can distribute. Haxelib libraries have one main `classPath`, so Reflaxe copies the configured `stdPaths` into that classpath. When a copied path ends in `_std`, Reflaxe renames the copied files to `.cross.hx`.

In simpler terms:

- in the source repo, newer Reflaxe targets can keep overrides as `std/<target>/_std/String.hx`
- in the flattened package, those same overrides may become `String.cross.hx`

That does not mean the source repo was wrong. It means the package was flattened.

## What the reference Reflaxe targets do

The local reference checkout `../haxe.compilerdev.reference` shows both strategies.

| Reference target | Source override style | What it means |
| --- | --- | --- |
| `reflaxe_go` | broad `src/**/*.cross.hx` | Older/direct model: std replacements are already on the initial haxelib classpath, so `.cross.hx` gates them to Haxe `cross` mode. |
| `reflaxe.CPP` | `std/cxx/_std/*.hx` plus `reflaxe.stdPaths` | Newer/template-style model: develop with a target `_std` tree; package tooling can flatten later. |
| `reflaxe.GDScript` | `std/gdscript/_std/*.hx` plus `reflaxe.stdPaths` | Same source-side `_std` model as C++. |
| `reflaxe.lua` | `std/rlua/_std/*.hx` plus `reflaxe.stdPaths` | Same source-side `_std` model as C++. |
| `reflaxe.CSharp` | declares `stdPaths`, but this checkout has no std files | Still follows the same metadata shape; there just is no local std override tree in that checkout. |
| Reflaxe framework template | `std/LANG/_std/*.hx` plus `stdPaths` | This is the starter shape Reflaxe generates for new targets. |

So `.cross.hx` is a real Reflaxe packaging convention, but it is not the only Reflaxe source convention.

The more precise rule is:

- direct `.cross.hx` files are good when your initial classpath intentionally contains the override files
- `_std/*.hx` files are good when your development model can inject a target-private std layer
- Reflaxe packaging may convert `_std/*.hx` into `.cross.hx` when flattening the package

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

The reason is the order of the current `reflaxe.ocaml` bootstrap:

1. `haxe_libraries/reflaxe.ocaml.hxml` puts `packages/reflaxe.ocaml/src/` on the classpath.
2. It also puts `packages/reflaxe.ocaml/std/` on the classpath.
3. It does **not** put `packages/reflaxe.ocaml/std/_std/` on the initial classpath.
4. `CompilerInit.Start()` has to be typed and run before `CompilerBootstrap.InjectClassPaths()` can add `std/_std`.

That creates a small early window where a core module can be requested before the OCaml `_std` layer exists.

For ordinary modules like `String`, `Array`, `Std`, and `Sys`, that is fine: they can wait until the OCaml target is known and `_std` has been injected.

The exception/stack cluster is different:

- `haxe.Exception` is used by Haxe exception typing and by `haxe.ValueException`.
- `haxe.NativeStackTrace` backs `haxe.Exception.stack` and `haxe.CallStack`.
- `haxe.ValueException` is needed when typed catch lowering wraps non-`Exception` throws.

If one of those resolves to the upstream extern declaration before the OCaml override is available, Haxe can cache the wrong module shape for the rest of the compilation. For Reflaxe custom targets, an extern-only module also means there may be no concrete emitted OCaml module later, which can become a link/runtime failure.

Putting these files under `src/haxe/*.cross.hx` makes them visible from the initial target library classpath. The `.cross.hx` suffix keeps them out of non-`cross` built-in targets, and the internal `#if ocaml_output` keeps the real OCaml implementation from leaking into non-OCaml custom-target/tooling contexts.

So the current OCaml split is:

- normal target-owned stdlib override: `_std/*.hx`
- early bootstrap-safe exception set: `src/**/*.cross.hx`

That is why `String` is in `_std`, while `haxe.Exception` is in `src/*.cross.hx`.

## Is the early `.cross.hx` set fundamental?

No. It is mostly a consequence of the current `reflaxe.ocaml` development/bootstrap shape.

Today, `reflaxe.ocaml` has this local setup:

- `src/` is on the initial haxelib classpath.
- `std/` is on the initial haxelib classpath.
- `std/_std/` is plain `.hx`, so we do **not** put it on the initial classpath for every build.
- `CompilerBootstrap` injects `std/_std/` later, only after it can tell this is an OCaml target build.

That makes a tiny early `src/haxe/*.cross.hx` set useful for modules that can be requested before the later injection.

If we adopt the fuller Reflaxe packaging convention, the boundary can move:

- source stays readable as `std/_std/*.hx`
- target-local dev/test tooling can add `std/_std` up front for OCaml-only runs
- the published haxelib package can flatten those `_std` files into `.cross.hx` files in the package classpath

In that packaged shape, there may be no need for a special early `src/haxe/` exception set, because the packaged `.cross.hx` overrides are already visible from the initial classpath.

That is the likely long-term cleanup direction, but it should be done as a packaging/dev-tooling change, not by simply renaming every source override to `.cross.hx`.

## What this means during `reflaxe.ocaml` development

During normal development in this repo, `reflaxe.ocaml` does not need a Reflaxe package-build step before it can use its std overrides.

The local development path is:

- `haxe_libraries/reflaxe.ocaml.hxml` adds `packages/reflaxe.ocaml/src/`
- the same hxml adds `packages/reflaxe.ocaml/std/`
- `CompilerBootstrap.InjectClassPaths()` adds `packages/reflaxe.ocaml/std/_std/` only when the build is actually selecting the OCaml target

That is very close to the source-side model used by `reflaxe.CPP`, `reflaxe.GDScript`, and `reflaxe.lua` in the reference checkout: keep `_std/*.hx` readable in the repo, then let the active target path decide when it is visible.

So yes: for local development, `std/_std/*.hx` is the intended shape and no Reflaxe flattening build is needed first.

## Why `String.cross.hx` would be too broad for OCaml

A file named `String.cross.hx` says:

- use this when the build is in generic `cross` mode

But `cross` is not the same thing as `ocaml`.

If you key a file only off `cross`, that file is a candidate for any custom-target build that reaches it, not just OCaml.

By contrast, `_std/String.hx` in `reflaxe.ocaml` says:

- use this only if the OCaml bootstrap explicitly adds the OCaml shadow stdlib layer

That is why `_std/String.hx` is the better fit here.

## Is direct `.cross.hx` also good?

Yes, when it matches the target's classpath and packaging model.

Direct `.cross.hx` is especially useful when:

- the file must be visible before target bootstrap can inject `_std`
- the package is flattened so override files live on the initial classpath
- the target intentionally uses Haxe `cross` file selection as its main override gate

That is why `reflaxe_go` can reasonably keep broad `.cross.hx` files directly in `src/`, and why Reflaxe's package build can reasonably rename copied `_std` files to `.cross.hx`.

The tradeoff is scope. `.cross.hx` means "visible to Haxe's generic `cross` platform", not "visible only to OCaml". If another custom target is active in the same compilation and the classpaths overlap, Haxe resolves one module by classpath order. It does not merge target versions.

For `reflaxe.ocaml`, that makes direct `.cross.hx` best for the small set of early files that truly need it, not for every ordinary std override during source development.

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

Choose a package-build conversion from `_std/Foo.hx` to `Foo.cross.hx` when:

- the source repo wants the clearer `_std` layout,
- but the published haxelib package has to flatten target std paths into one classpath.

That conversion should be explicit and tested. It should not be something contributors have to remember manually.

## Packaging follow-up for `reflaxe.ocaml`

`reflaxe.ocaml` currently has a good local-development story, but the eventual published haxelib package needs an explicit packaging story.

Before publishing a flattened haxelib, we should decide whether to:

- reuse Reflaxe's `stdPaths` build behavior,
- implement an equivalent `reflaxe.ocaml` package script,
- or keep a package shape that preserves conditional bootstrap injection without flattening.

Whichever path we choose, the packaged artifact should prove these things:

- `packages/reflaxe.ocaml/std/_std/*.hx` overrides are available for OCaml target builds
- those overrides do not become plain always-on `.hx` files in the package classpath
- early `src/haxe/*.cross.hx` files still resolve before bootstrap needs them
- a simple upstream Haxe compile works from the packaged artifact, not only from `haxelib dev`
- mixed-target activation either fails clearly or avoids silent classpath-order collisions

The likely near-term answer is to add a package-build step that mirrors Reflaxe's behavior: keep `_std/*.hx` in source, then copy/package those files as `.cross.hx` only for the distributable haxelib shape.

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
