# Compatibility Matrix (Portable vs OCaml-native)

This document is the “what works today?” summary for `reflaxe.ocaml`.

It has two goals:

1) Help users choose between the **portable** surface (Haxe-first) and the **OCaml-native**
   surface (`ocaml.*`, OCaml-first).
2) Make current limitations explicit so you don’t have to discover them via trial-and-error.

For deeper implementation details, see:

- `docs/01-getting-started/TESTING.md:1` (testing layers)
- `docs/02-user-guide/M10_LANGUAGE_SURFACE_AUDIT.md:1` (portable semantics checklist)
- `docs/02-user-guide/STDLIB_COVERAGE_PLAN.md:1` (portable stdlib plan)
- `docs/02-user-guide/OCAML_NATIVE_MODE.md:1` (OCaml-native surface)
- `docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md:1` (portable vs metal runtime module status)

## Surfaces

### Portable (default)

- Write “normal Haxe”.
- Backend + runtime shims preserve Haxe semantics.
- Goal: same code can often compile to OCaml and to other Haxe targets.

### OCaml-native (`ocaml.*`)

- Opt-in APIs that map more directly to OCaml idioms and ecosystems.
- Goal: “Haxe typing + tooling”, but OCaml-native types (`'a list`, `option`, `Stdlib.Hashtbl.t`, …).
- Not expected to be portable.

## Language features (portable)

Legend:

- ✅ supported (continuously tested)
- 🟡 partially supported / edge cases remain
- ❌ not supported yet

| Feature | Status | Notes / References |
|---|---:|---|
| Constants, locals, sequencing | ✅ | Covered by M2+ integration + fixtures |
| Function literals + calls | ✅ | Includes unit-call convention |
| `if` / `else` | ✅ | Fixtures + integration |
| `switch` (enums/values) | ✅ | Lowered to OCaml `match` |
| `while` + `break/continue` | ✅ | `break/continue` via control exceptions |
| `do { } while` | ✅ | Covered by portable fixtures |
| Enums + constructor args | ✅ | Snapshot + integration |
| Classes | ✅ | Record-backed instances |
| Inheritance + overrides | ✅ | Dispatch records; see `M10_LANGUAGE_SURFACE_AUDIT.md` |
| Interfaces dispatch | ✅ | Covered by portable fixtures |
| `try/catch`, typed catches | ✅ | Tagged throw strategy; see `TRY_CATCH_AND_EXCEPTIONS.md` |
| Exception parity (full) | 🟡 | Best-effort parity; see `TRY_CATCH_AND_EXCEPTIONS.md` for the portable strategy |
| Method-as-value (`obj.method`) | ✅ | Covered by portable fixtures |
| Reflect/dynamic field access | 🟡 | Portable subset: `Reflect.field/setField/hasField/callMethod` (other APIs still evolving) |

## Stdlib coverage (portable)

This table is “what we validate continuously” for the current portable surface.
Full portable stdlib parity is tracked against:

- `docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`
- `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_OCAML_4_3_7.json` (tiered gate scope)
- `docs/00-project/STDLIB_PORTABLE_EVIDENCE_OCAML_4_3_7.json` (runtime/lowering/passthrough evidence)
- `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`

Matrix status taxonomy:

- `override` | `runtime_backed` | `lowering_intrinsic` | `passthrough_verified` | `passthrough_unverified`

| Module / Area | Status | Notes |
|---|---:|---|
| `Array<T>` | ✅ | `packages/reflaxe.ocaml/std/_std/Array.hx` + `packages/reflaxe.ocaml/std/runtime/HxArray.ml` |
| `String` | ✅ | `packages/reflaxe.ocaml/std/_std/String.hx` + `packages/reflaxe.ocaml/std/runtime/HxString.ml` |
| `haxe.io.Bytes` | ✅ | Runtime-backed (lowered in codegen) |
| `Date` | ✅ | `packages/reflaxe.ocaml/std/_std/Date.hx` + `packages/reflaxe.ocaml/std/runtime/Date.ml` |
| `Sys` | ✅ | `packages/reflaxe.ocaml/std/_std/Sys.hx` + `packages/reflaxe.ocaml/std/runtime/HxSys.ml` |
| `sys.FileSystem` | ✅ | `packages/reflaxe.ocaml/std/_std/sys/FileSystem.hx` + `packages/reflaxe.ocaml/std/runtime/HxFileSystem.ml` |
| `sys.io.File` | ✅ | Runtime subset exercised by fixtures/examples |
| `haxe.ds.Map` / `haxe.ds.*` | ✅ | Runtime `HxMap.ml` + codegen lowering |
| `EReg` | ✅ | `packages/reflaxe.ocaml/std/_std/EReg.hx` + `packages/reflaxe.ocaml/std/runtime/EReg.ml` |
| `Math` | ✅ | `packages/reflaxe.ocaml/std/_std/Math.hx` + `packages/reflaxe.ocaml/std/runtime/Math.ml` |

## OCaml-native surface (`ocaml.*`)

| API | Status | Notes |
|---|---:|---|
| `ocaml.List<T>` / `Option<T>` / `Result<T,E>` | ✅ | Emitted as real OCaml ADTs |
| `ocaml.Ref<T>` | ✅ | Emitted as real OCaml refs (`ref` / `!` / `:=`) |
| `ocaml.Array<T>` | ✅ | Typed wrapper over `Stdlib.Array` |
| `ocaml.Bytes` | ✅ | Typed wrapper over `Stdlib.Bytes` |
| `ocaml.Char` | ✅ | Typed wrapper over `Stdlib.Char` |
| `ocaml.Hashtbl<K,V>` | ✅ | Typed wrapper over `Stdlib.Hashtbl` |
| `ocaml.Seq<T>` | ✅ | Typed wrapper over `Stdlib.Seq` |
| `ocaml.StringMap/IntMap` + `StringSet/IntSet` | ✅ | Emitted functor instantiations (`OcamlNative*`) |
| Labelled args interop (`@:ocamlLabel`) | ✅ | See `OCAML_INTEROP_LABELLED_ARGS.md` |

## Tooling / build integration

| Feature | Status | Notes |
|---|---:|---|
| Dune scaffolding | ✅ | Emits `dune-project`, `dune`, runtime library |
| Build after emit | ✅ | `-D ocaml_build=native|byte`, `-D ocaml_run` |
| `.mli` inference | ✅ | `-D ocaml_mli` (`ocamlc -i`) |
| Stable error locations | ✅ | Line directives (`# 1 "File.ml"`) by default |
| Dune layouts | ✅ | `-D ocaml_dune_layout=lib`, `-D ocaml_dune_exes=...` |

## Macro / HXHX status (bootstrapping path)

- `hxhx` is a bring-up harness and stage0 shim by default, with explicit Stage 1/3 flags for bootstrap rungs.
- Macro transport and Stage 4 API overrides exist for bring-up and CI selftests, but upstream “replacement” gates
  are still tracked separately.
- See:
  - `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`
  - `docs/02-user-guide/HXHX_DISTRIBUTION.md:1`
