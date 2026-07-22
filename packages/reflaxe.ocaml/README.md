# reflaxe.ocaml

MIT-licensed [Reflaxe](https://github.com/SomeRanDev/reflaxe) target that compiles Haxe to OCaml, with runtime/dune scaffolding for native builds.

This package is developed in the `hxhx` monorepo and is also usable with mainstream upstream Haxe workflows.

## What it provides

- Haxe → OCaml code generation (`.ml` files).
- Runtime support files under `std/runtime/`.
- Optional dune project emission (`dune`, `dune-project`).
- Optional post-emit native build/run helpers.
- Optional OCaml-native surface (`ocaml.*` types like `Option`, `Result`, `List`, `Hashtbl`, `Seq`, `Bytes`, `Buffer`).

The current native surface is deliberately smaller than the complete OCaml
ecosystem. The checked plan for external packages, generated bindings, typed
adapters, and Haxe-friendly wrappers is documented in
[`OCAML_ECOSYSTEM_FROM_HAXE.md`](../../docs/02-user-guide/OCAML_ECOSYSTEM_FROM_HAXE.md).

## Requirements

- Haxe `4.3.7`
- Reflaxe `4.x`
- OCaml + dune + ocaml-findlib (for native build/run)

## Check your development environment

After installing the package, ask the target to diagnose the current project:

```bash
haxelib run reflaxe.ocaml doctor
```

The report separates four useful capability levels:

- `source`: stock Haxe can resolve the target and emit OCaml;
- `native`: OCaml, Dune, and findlib can build that output;
- `compiler`: compiler-libs is also available for advanced compiler tooling;
- `hxhx`: an `hxhx` executable is available as an additional host.

Use `--require` when a script needs one level to fail closed, and `--json` for a
stable machine-readable report:

```bash
haxelib run reflaxe.ocaml doctor --require native
haxelib run reflaxe.ocaml doctor --json --require compiler
```

Inside this monorepo, use the source-checkout command instead:

```bash
npm run doctor:reflaxe-ocaml -- --require native
```

The contributor command deliberately compiles only the host-side diagnostic
tool. The checkout's target `_std` classpaths are broader than the flattened
installed package, so using the direct command avoids pretending that the
doctor itself is an OCaml-target application.

`PASS` means the named check worked. `WARN` means the tool is usable or missing
only for an optional capability, but differs from the exact hosted evidence
lane. `SKIP` is informational, such as an optional hxhx host or a future
manifest that the current package does not claim to ship. The doctor never
installs packages or changes project files.

## Create a starter project

The installed package includes tested application and library templates:

```bash
haxelib run reflaxe.ocaml new app my-app --name "My App"
haxelib run reflaxe.ocaml new library my-library --name "My Library"
```

The destination must have an existing parent and must not already exist. The
command renders the complete project in a sibling staging directory and renames
it into place only after every file is written, so it never merges with or
overwrites user files.

The application template builds and runs a native executable. The library
template contains a Haxe-facing package and builds a library-only Dune project;
it does not present inferred `.mli` files as a stable public OCaml ABI. Binding,
native-adapter, plugin, and target scaffolds remain unavailable until their
typed manifests and shared SDK contracts land, and requests for them fail
without creating a directory.

## Fast build and watch loop

For an installed package, run the project's normal `build.hxml` through the
package command:

```bash
haxelib run reflaxe.ocaml build
haxelib run reflaxe.ocaml build --run out/_build/default/out.exe
haxelib run reflaxe.ocaml watch --run out/_build/default/out.exe
```

`watch` discovers classpaths and included HXML files, waits for an edit batch to
settle, then rebuilds and optionally runs the native artifact. Use repeated
`--watch-path` options for inputs outside those discovered roots. Generated
output and common build/cache directories are excluded, and the post-build
input snapshot prevents compiler output from triggering another build.

Each batch starts a fresh Haxe process. Persistent Haxe-server reuse is not used
because current Reflaxe evidence found an incomplete-output failure on that
route. Iteration still benefits from content-stable generated files and Dune's
incremental native build cache. `--max-builds` provides a deterministic stopping
point for tests and automation; run `haxelib run reflaxe.ocaml watch --help` for
all options.

For a plain-language explanation of compilation servers, upstream Haxe setup,
the current `reflaxe.ocaml` and `hxhx` defaults, editor and CI scenarios, memory
guidance, and troubleshooting, read
[`COMPILATION_SERVER.md`](../../docs/01-getting-started/COMPILATION_SERVER.md).

The command requests `ocaml_build_timing_report.json` and reports three honest
boundaries: total Haxe-child time, target-owned subprocess time, and the Dune
build duration. Dune currently combines OCaml typechecking, compilation, and
linking; the report does not guess cache hits or claim separate load, startup,
or workload-runtime timing. Use `--output <directory>` when the project does not
emit to `out/`.

## Inspect a completed build

After `build`, explain the artifacts and decisions the current compiler owns:

```bash
haxelib run reflaxe.ocaml inspect
haxelib run reflaxe.ocaml inspect --require-lowering
haxelib run reflaxe.ocaml inspect --json
```

Every successful compilation now writes `ocaml_artifact_manifest.json`. It
names every compiler-owned non-cache file—not only Haxe modules—along with the
component that produced it, its role, byte count, SHA-256 digest, and whether it
belongs in a reproducible source bundle. `inspect` rechecks those files and
fails if one is missing, modified, duplicated, or unknown. It also validates
Reflaxe's narrower generated-module receipt, optional native Dune timing, the
active OCaml profile, and the current runtime-selection report. When the HXML contains
`-D ocaml_lowering_report` (included in the starter templates), it also shows
the source location, semantic and carrier types, representation reason, effect
order, and runtime requirements for assignment/update operations already on the
typed place-lowering path. The same report inventories mutable static fields
before code generation, including where each OCaml `ref` cell is declared and
where its Haxe initializer runs. It also records direct dependencies between
initializers. This makes cross-type and cross-module ordering reviewable
without reconstructing it from generated source, and lets the compiler reject
an initializer cycle with a Haxe-facing diagnostic before invoking the OCaml
build. It also rejects a same-module storage type that cannot be declared in
Haxe initialization order, rather than emitting an unbound OCaml type. `--output`
selects a non-default project-relative output directory.

This is intentionally honest inspection, not generated-code guesswork. The
artifact inventory is valid today, but it reports source-bundle packaging as
blocked until every runtime need and native dependency has an explicit, locked
explanation. Runtime-enabled builds now write
`ocaml_runtime_requirement_report.json`: it traces typed assignments and
updates, the compiler-generated type registry, declared static native runtime
boundaries such as `HxStdio`, `HxBacktrace`, and `HxFPHelper`, and the core
packaging rule to the exact checked runtime files that were packaged. The
report labels itself `partial`, lists which observed module names are directly
selected by at least one recorded compiler reason, and lists which are not.
This name overlap does not mean every use site is explained. The existing
runtime selection report
therefore remains the current compiler/runtime report, not a complete
explanation for the whole program.
Program-wide representation, native dependency, raw/unsafe, typed binding, and
curated export-ABI inspection remain visibly unavailable until their owning
checked records land. The command never scans emitted OCaml or Dune text to
fabricate those answers.

Treat `ocaml_output` as compiler-owned. Do not place handwritten `.ml`, `.mli`,
or project files inside it: an unattributed file now stops the build instead of
silently entering a later package. Keep native sources outside the generated
directory until the structured adapter/dependency workflow is available.

## Quickstart (inside this monorepo)

From repo root:

```bash
npm install
npx lix download
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Build emitted OCaml natively:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

## Minimal starter project

Create `Main.hx`:

```haxe
class Main {
	static function main() {
		Sys.println("Hello from reflaxe.ocaml");
	}
}
```

Compile it to OCaml (from the same directory as `Main.hx`):

```bash
haxe -cp . -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

Inside this monorepo, `haxe_libraries/reflaxe.ocaml.hxml` makes that command
resolve this source checkout and supplies the source `_std` classpath before
typing starts. Outside this monorepo, prefer the released haxelib package or a
locally built package zip. Use `haxelib dev` only when you intentionally want an
external project to test this unreleased checkout. Point that temporary override
at the repo root dev package, not raw `packages/reflaxe.ocaml`, so the source
`_std` path is supplied:

```bash
cd /path/to/my-haxe-app
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
```

Build/run manually with dune:

```bash
cd out
dune build ./*.exe
dune exec ./out.exe
```

## Using with mainstream upstream Haxe

If you want upstream Haxe CLI + `reflaxe.ocaml` outside `hxhx` workflows, the
normal shape is an installed package:

```bash
haxelib install reflaxe.ocaml
```

For unreleased checkout testing only, use a temporary local override:

```bash
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
```

Then compile as usual:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

For a focused guide, see:
- [`docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`](../../docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md)
- [`docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`](../../docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md)

## Std override layout

During local development, `reflaxe.ocaml` keeps target-owned stdlib overrides in `std/ocaml/_std/*.hx`.

Those files do not need to be renamed to `.cross.hx` before local builds. The package layout follows the shape generated by `haxelib run reflaxe new`: `std/` contains target APIs/runtime support, and `std/ocaml/_std` contains OCaml replacements for upstream stdlib modules. The monorepo library config supplies those `stdPaths` explicitly, the same way Reflaxe's own dev/test command does.

Published haxelib packages are built with Reflaxe's own flattening step. `haxelib run reflaxe build` copies `std/ocaml/_std/*.hx` into the package classpath as `.cross.hx`, so the distributable package keeps Reflaxe's `.cross.hx` convention without forcing source development to maintain generated package files by hand.

That source/package difference matters for `haxelib dev`: pointing an external
project at the repo root uses this monorepo's dev package metadata and root
`extraParams.hxml`, which add the source `_std` classpath directly. Pointing at
raw `packages/reflaxe.ocaml` does not perform Reflaxe's flattening step, so
those `_std` overrides would not become `.cross.hx` first.

That is why `haxelib dev` is a troubleshooting/testing tool here, not the main
recommendation:

- it mutates local haxelib resolution state outside this repo,
- it can bypass the package build that creates `.cross.hx` files,
- and it can hide bugs that only appear in the real flattened package.

The better default is:

- use `haxe_libraries/reflaxe.ocaml.hxml` for monorepo development,
- use `npm run test:reflaxe-ocaml:package-install` for release-package
  validation,
- use the released haxelib package for normal external projects.

The package-install proof builds the versioned ZIP twice and requires identical
SHA-256 values. It stages only Git-tracked source inputs, rejects OCaml compiler
outputs such as `.cmi`, `.cmo`, and `.cmxs`, installs the target in a disposable
haxelib repository, then compiles and runs an external application with stock
Haxe 4.3.7. This prevents a machine-local `haxelib dev` link or a compiler-
version-specific OCaml binary from making a broken package appear healthy.
Evidence is written to `.artifacts/reflaxe-ocaml/package-install/summary.json`.

The CI package matrix builds that source ZIP once and gives the exact artifact
and manifest to clean Ubuntu and macOS consumers. The aggregate marker
`RO_PACKAGE_ARTIFACT_MATRIX:PASS` is emitted only when both consumers install,
compile, build, and run the same package SHA. This is verified-host evidence,
not yet a blanket Linux/macOS/Windows support declaration.

To build only the deterministic archive, use:

```bash
bash scripts/release/build-haxelib-zip.sh
```

This changed because `reflaxe.ocaml` originally grew in this monorepo without being bootstrapped from `reflaxe new`. The current layout is intentionally closer to a generated Reflaxe compiler while preserving the established `ocaml_output` define and runtime behavior. See [`docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`](../../docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md).

## What `extraParams.hxml` does

`extraParams.hxml` is loaded when Haxe resolves `-lib reflaxe.ocaml` through
haxelib. It supplies the target setup users should not have to type manually:

```hxml
-D ocaml
-D retain-untyped-meta
--macro nullSafety("reflaxe.ocaml")
--macro reflaxe.ocaml.CompilerInit.Start()
```

It does not flatten package files, and `CompilerInit.Start()` is not responsible
for making `_std` visible. In source checkout mode, `_std` visibility has to
come from explicit initial classpath wiring before typing starts:

- monorepo examples/tests use `haxe_libraries/reflaxe.ocaml.hxml`
- repo-root `haxelib dev` uses the root dev package metadata and
  `extraParams.hxml`

In a built package, `_std` visibility comes from Reflaxe build output instead:
`std/ocaml/_std/*.hx` files are copied into the package classpath as
`.cross.hx`.

## Required define

`reflaxe.ocaml` requires:

```bash
-D ocaml_output=<output-dir>
```

Without `ocaml_output`, OCaml target output is not selected.

## Common defines

- `-D ocaml_build=native|byte`: run dune build after emit.
- `-D ocaml_build_timing_report`: write receipt-linked target-owned Dune phase timings (the package `build` and `watch` commands request this automatically).
- `-D ocaml_run`: run emitted executable via dune after emit.
- `-D ocaml_no_dune`: disable dune scaffolding emission.
- `-D ocaml_dune_layout=exe|lib|plugin`: choose dune layout.
- `-D ocaml_dune_exes=name:MainModule[,name2:Main2]`: multi-executable dune stanza.
- `-D ocaml_plugin_mode=1`: plugin-packaging defaults for `ocaml_dune_layout=plugin` (currently disables package alias helpers unless you explicitly set `-D ocaml_emit_package_aliases=1`).
- `-D ocaml_plugin_run_main=1`: in `ocaml_dune_layout=plugin`, run the resolved Haxe main module from the dynlink entry module instead of emitting a no-op entrypoint.
- `-D ocaml_plugin_register_provider=<pluginId>:<providerType>`: in `ocaml_dune_layout=plugin`, emit a dynlink entry module that registers an `hxhx` backend provider without executing generated Haxe/std modules.
- `-D ocaml_plugin_load_marker=<text>`: optional marker printed by `ocaml_plugin_register_provider` entry modules for smoke-test evidence.
- `-D ocaml_module_prefix=<Prefix_>`: prefix emitted Haxe compilation units so multiple plugin outputs can coexist without module-name collisions.
- `-D ocaml_emit_exclude_packages=a.b,c.d`: omit emitted Haxe module units whose package path starts with one of the configured prefixes.
- `-D ocaml_emit_exclude_paths=Foo,bar/`: omit emitted artifacts by output-relative path prefix (useful for root modules like `HxTypeRegistry` or `Any`).
- `-D ocaml_mli` or `-D ocaml_mli=infer|all`: generate `.mli` via `ocamlc -i`.
- `-D ocaml_sourcemap=directives`: add line directives for error mapping.
- `target.threaded` is auto-defined on OCaml target builds (`sys.thread.*` is runtime-backed via `HxThread`).

## Relationship to hxhx

- `hxhx` is the main compiler product in this repo.
- `reflaxe.ocaml` is both:
  - a standalone backend/runtime package for upstream Haxe users, and
  - a core implementation dependency used by `hxhx` bootstrap/native lanes.

## Related docs

- [`README.md` (repo root)](../../README.md)
- [`docs/01-getting-started/START_HERE.md`](../../docs/01-getting-started/START_HERE.md)
- [`docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`](../../docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md)
- [`docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`](../../docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md)
- [`docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`](../../docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md)
- [`docs/00-project/REFLAXE_OCAML_REPOSITORY_EXTRACTION_GATE.md`](../../docs/00-project/REFLAXE_OCAML_REPOSITORY_EXTRACTION_GATE.md)
- [`docs/01-getting-started/TESTING.md`](../../docs/01-getting-started/TESTING.md)
- [`docs/02-user-guide/HXHX_BACKEND_LAYERING.md`](../../docs/02-user-guide/HXHX_BACKEND_LAYERING.md)
- [`docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`](../../docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md)

## License

MIT. See [`LICENSE`](../../LICENSE).
