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

A file like `std/<target>/_std/String.hx` is just a normal `String.hx`, but it lives in a classpath that is inserted ahead of the mainstream stdlib.

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

So "needed before bootstrap can add `_std`" is a real reason to use direct `.cross.hx`, but it is not the main pattern shown by the reference sample compilers in `haxe.compilerdev.reference`. `reflaxe.ocaml` used to have a small early `src/haxe/` exception set for this reason; this refactor removes that bespoke source shape and follows the generated Reflaxe model where source dev/test tooling supplies `stdPaths` explicitly.

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

## Where `extraParams.hxml` fits

`extraParams.hxml` is the haxelib hook file for a library.

When a project passes `-lib reflaxe.ocaml`, Haxe resolves the library and reads
the library's extra parameters as if the user had written those arguments on the
command line. For `reflaxe.ocaml`, the package-level file provides the common
target setup:

```hxml
-D ocaml
-D retain-untyped-meta
--macro nullSafety("reflaxe.ocaml")
--macro reflaxe.ocaml.CompilerInit.Start()
```

That file registers the compiler, but it is not a package builder. It does not
copy files, flatten directories, or rename `_std/*.hx` files to `.cross.hx`.

This matters because the source checkout and the package artifact have different
ways to make target std overrides visible:

| Shape | How std overrides become visible |
| --- | --- |
| Monorepo examples/tests | `haxe_libraries/reflaxe.ocaml.hxml` adds `packages/reflaxe.ocaml/std/ocaml/_std/` directly. |
| Repo-root `haxelib dev` override | root `extraParams.hxml` adds `packages/reflaxe.ocaml/std/ocaml/_std/` directly for external checkout testing. |
| Raw `packages/reflaxe.ocaml` source | `extraParams.hxml` registers the target, but raw `_std` files are not flattened by haxelib itself. |
| Built/released package | Reflaxe build copies `_std/*.hx` into the package classpath as `.cross.hx`; the package `extraParams.hxml` only has to register the target. |

So `extraParams.hxml` participates in every haxelib-style `-lib reflaxe.ocaml`
resolution, not only `haxelib dev`. The risky part is assuming it also performs
Reflaxe's package flattening. It does not.

That is why `haxelib dev` is a narrow tool for testing an unreleased checkout:

- pointing it at the repo root uses monorepo dev wiring and can hide package
  build mistakes,
- pointing it at raw `packages/reflaxe.ocaml` skips the `_std` to `.cross.hx`
  conversion,
- and release validation still needs to test the flattened zip produced by
  `bash scripts/release/build-haxelib-zip.sh`.

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

- `packages/reflaxe.ocaml/std/ocaml/_std/String.hx`
- `packages/reflaxe.ocaml/std/ocaml/_std/Array.hx`
- `packages/reflaxe.ocaml/std/ocaml/_std/Sys.hx`

That matches the current source-checkout bootstrap model:

- `std/` is always added for the haxelib surface,
- `std/ocaml/_std` is supplied by OCaml target entrypoints such as `-lib reflaxe.ocaml` and package/dev test tooling.

So `_std/String.hx` means:

- this is the OCaml target's `String`,
- not a generic cross-target `String`,
- and it should only appear after OCaml-specific gating is active.

That is narrower and easier to reason about than a generic `String.cross.hx`.

## Why source `reflaxe.ocaml` does not keep early `.cross.hx` files

The previous local layout kept three source files under `src/haxe/*.cross.hx`:

- `haxe.Exception`
- `haxe.NativeStackTrace`
- `haxe.ValueException`

That worked, but it was not the shape Reflaxe generates for new compilers. It also made source development look different from the Reflaxe template for a reason that was mostly accidental: `reflaxe.ocaml` was started without `haxelib run reflaxe new`, so the project grew a bespoke package/dev layout.

The current source layout moves those files into `std/ocaml/_std/haxe/*.hx` with the rest of the OCaml stdlib overrides.

The source-development visibility problem is handled by the local hxml/tooling instead:

1. `haxe_libraries/reflaxe.ocaml.hxml` puts `packages/reflaxe.ocaml/src/` on the classpath.
2. It also puts `packages/reflaxe.ocaml/std/` on the classpath.
3. It also puts `packages/reflaxe.ocaml/std/ocaml/_std/` on the classpath.
4. `CompilerInit.Start()` then registers the compiler, like a generated Reflaxe compiler init macro.

That removes the source-side early `src/haxe/*.cross.hx` exception set and keeps the source checkout close to generated Reflaxe expectations.

For ordinary modules like `String`, `Array`, `Std`, and `Sys`, that is fine: the OCaml library configuration makes the whole OCaml `_std` layer visible for `-lib reflaxe.ocaml` source builds, so they do not need a special early source-side `.cross.hx` home.

The exception/stack cluster is different:

- `haxe.Exception` is used by Haxe exception typing and by `haxe.ValueException`.
- `haxe.NativeStackTrace` backs `haxe.Exception.stack` and `haxe.CallStack`.
- `haxe.ValueException` is needed when typed catch lowering wraps non-`Exception` throws.

If one of those resolves to the upstream extern declaration before the OCaml override is available, Haxe can cache the wrong module shape for the rest of the compilation. For Reflaxe custom targets, an extern-only module also means there may be no concrete emitted OCaml module later, which can become a link/runtime failure.

The new rule is: make `std/ocaml/_std` visible before compiler init, not by keeping special source files in `src/haxe/`.

So the current OCaml split is:

- source target-owned stdlib overrides: `std/ocaml/_std/*.hx`
- published flattened package overrides: `src/**/*.cross.hx` generated by `haxelib run reflaxe build`

That is why `String`, `haxe.Exception`, `haxe.NativeStackTrace`, and `haxe.ValueException` now all live in `_std` in source.

## Is the early `.cross.hx` set fundamental?

No. This refactor removes it from the source checkout.

The distinction now is source layout versus package layout:

- source stays readable as `std/ocaml/_std/*.hx`
- local source builds add `std/ocaml/_std` through dev/test hxml classpaths
- release packaging runs Reflaxe's own build step, which flattens `_std` files into `.cross.hx`

The flattened package shape still uses `.cross.hx`, but those files are build output, not hand-maintained source files.

This keeps the source checkout close to what `haxelib run reflaxe new OCaml ocaml ml direct` would create, while preserving the established `ocaml_output` define and the existing `reflaxe.ocaml` compiler/runtime implementation.

## What this means during `reflaxe.ocaml` development

During normal development in this repo, `reflaxe.ocaml` does not need a Reflaxe package-build step before it can use its std overrides.

The local development path is:

- `haxe_libraries/reflaxe.ocaml.hxml` adds `packages/reflaxe.ocaml/src/`
- the same hxml adds `packages/reflaxe.ocaml/std/`
- `haxe_libraries/reflaxe.ocaml.hxml` adds `packages/reflaxe.ocaml/std/ocaml/_std/`, mirroring Reflaxe's dev/test command that supplies `stdPaths` from `haxelib.json`

That is close to the source-side model generated by Reflaxe and used by reference targets such as `reflaxe.CPP`, `reflaxe.GDScript`, and `reflaxe.lua`: keep `_std/*.hx` readable in the repo, then have source tooling supply the configured `stdPaths` while developing the target.

So yes: for local development, `std/ocaml/_std/*.hx` is the intended source shape and no Reflaxe flattening build is needed first.

## Why `String.cross.hx` would be too broad for OCaml

A file named `String.cross.hx` says:

- use this when the build is in generic `cross` mode

But `cross` is not the same thing as `ocaml`.

If you key a file only off `cross`, that file is a candidate for any custom-target build that reaches it, not just OCaml.

By contrast, `_std/String.hx` in `reflaxe.ocaml` says:

- use this only when the OCaml target's source tooling or package build explicitly supplies the OCaml shadow stdlib layer

That is why `_std/String.hx` is the better fit here.

## Is direct `.cross.hx` also good?

Yes, when it matches the target's classpath and packaging model.

Direct `.cross.hx` is especially useful when:

- the file must be visible before target bootstrap can inject `_std`
- the package is flattened so override files live on the initial classpath
- the target intentionally uses Haxe `cross` file selection as its main override gate

That is why `reflaxe_go` can reasonably keep broad `.cross.hx` files directly in `src/`, and why Reflaxe's package build can reasonably rename copied `_std` files to `.cross.hx`.

The tradeoff is scope. `.cross.hx` means "visible to Haxe's generic `cross` platform", not "visible only to OCaml". If another custom target is active in the same compilation and the classpaths overlap, Haxe resolves one module by classpath order. It does not merge target versions.

For `reflaxe.ocaml`, direct `.cross.hx` is now a package-output shape. Source development uses `_std` and lets the build/package step create `.cross.hx` when a flattened haxelib needs it.

## A simple decision rule

Choose `_std/Foo.hx` when:

- `Foo` is a normal target-owned stdlib override,
- target source tooling can supply the configured `_std` path,
- and the override should only appear for that target.

Choose `src/.../Foo.cross.hx` when:

- `Foo` must be visible even when you cannot rely on target `stdPaths`,
- or early macro/bootstrap typing will fail without it,
- and you still want to keep the file gated to `cross` rather than making it a plain always-visible `.hx` file.

`reflaxe.ocaml` no longer uses this shape for its source overrides because monorepo/dev tooling supplies `std/ocaml/_std` explicitly, and release packaging produces the `.cross.hx` form.

Choose `std/Foo.cross.hx` or `_std/Foo.cross.hx` when:

- your target intentionally uses `cross`-mode file selection as the main override strategy,
- and your bootstrap/classpath model is built around that.

Choose a package-build conversion from `_std/Foo.hx` to `Foo.cross.hx` when:

- the source repo wants the clearer `_std` layout,
- but the published haxelib package has to flatten target std paths into one classpath.

That conversion should be explicit and tested. It should not be something contributors have to remember manually.

## Packaging for `reflaxe.ocaml`

`reflaxe.ocaml` now has an explicit Reflaxe-style packaging path.

The source package root is `packages/reflaxe.ocaml/` and contains:

- `haxelib.json` with `classPath: "src/"`
- `extraParams.hxml`
- compiler code in `src/`
- target APIs and runtime files in `std/`
- target stdlib overrides in `std/ocaml/_std/`

The release script invokes Reflaxe's build runner, equivalent to:

```bash
haxelib run reflaxe build _Build --deleteOldFolder
```

from a temporary copy of that package root.

That lets Reflaxe do the same flattening it does for generated targets:

- copy `src/` into the build package,
- copy `std/` into that classpath,
- skip `std/ocaml/_std` during the broad `std/` copy,
- copy `std/ocaml/_std` into the classpath as `.cross.hx`,
- sanitize `haxelib.json` by removing the `reflaxe` build metadata.

The package smoke should prove:

- source `packages/reflaxe.ocaml/std/ocaml/_std/*.hx` overrides become packaged `.cross.hx` files,
- a simple upstream Haxe compile works from the packaged artifact,
- OCaml std overrides are available for OCaml target builds,
- mixed-target activation either fails clearly or avoids silent classpath-order collisions.

## How sibling targets differ

Within the current family of repos, the pattern is not uniform.

`reflaxe.ocaml`
- `_std` is the main target-owned stdlib layer.
- `.cross.hx` is produced by Reflaxe package flattening, not hand-maintained in source.

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

- OCaml owns `std/ocaml/_std/haxe/Exception.hx` in source and `src/haxe/Exception.cross.hx` in flattened packages
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
- `reflaxe.ocaml` now keeps source overrides under `std/ocaml/_std` and relies on Reflaxe package flattening to produce `.cross.hx` files for published packages.
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
