# reflaxe.ocaml

MIT-licensed [Reflaxe](https://github.com/SomeRanDev/reflaxe) target that compiles Haxe to OCaml, with runtime/dune scaffolding for native builds.

This package is developed in the `hxhx` monorepo and is also usable with mainstream upstream Haxe workflows.

## What it provides

- Haxe → OCaml code generation (`.ml` files).
- Runtime support files under `std/runtime/`.
- Optional dune project emission (`dune`, `dune-project`).
- Optional post-emit native build/run helpers.
- Optional OCaml-native surface (`ocaml.*` types like `Option`, `Result`, `List`, `Hashtbl`, `Seq`, `Bytes`, `Buffer`).

## Requirements

- Haxe `4.3.7`
- Reflaxe `4.x`
- OCaml + dune + ocaml-findlib (for native build/run)

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

If you are outside this monorepo, run `haxelib dev reflaxe.ocaml /path/to/hxhx` once before that command.

Build/run manually with dune:

```bash
cd out
dune build ./*.exe
dune exec ./out.exe
```

## Using with mainstream upstream Haxe

If you want upstream Haxe CLI + `reflaxe.ocaml` (outside `hxhx` workflows), point `haxelib` to this repo checkout:

```bash
haxelib dev reflaxe.ocaml /path/to/hxhx
```

Then compile as usual:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

For a focused guide, see:
- [`docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`](../../docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md)
- [`docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`](../../docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md)

## Std override layout

During local development, `reflaxe.ocaml` keeps normal target-owned stdlib overrides in `std/_std/*.hx`.

Those files do not need to be renamed to `.cross.hx` before local builds. The monorepo library config adds `std/`, and `CompilerBootstrap` injects `std/_std` only when the OCaml target is selected.

The few `.cross.hx` files under `src/haxe/` are early bootstrap exceptions that must be visible before `_std` injection is available. They cover the exception/stack cluster (`haxe.Exception`, `haxe.NativeStackTrace`, and `haxe.ValueException`) so upstream extern versions are not resolved and cached before the OCaml runtime-backed modules are visible.

For published haxelib packaging, we may still need a flattening step similar to Reflaxe's own `haxelib run reflaxe build`, where `_std` files are copied into the package classpath as `.cross.hx`. See [`docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`](../../docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md).

## Required define

`reflaxe.ocaml` requires:

```bash
-D ocaml_output=<output-dir>
```

Without `ocaml_output`, OCaml target output is not selected.

## Common defines

- `-D ocaml_build=native|byte`: run dune build after emit.
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
- [`docs/01-getting-started/TESTING.md`](../../docs/01-getting-started/TESTING.md)
- [`docs/02-user-guide/HXHX_BACKEND_LAYERING.md`](../../docs/02-user-guide/HXHX_BACKEND_LAYERING.md)
- [`docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`](../../docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md)

## License

MIT. See [`LICENSE`](../../LICENSE).
