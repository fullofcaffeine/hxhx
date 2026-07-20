# Using The OCaml Ecosystem From Haxe

The product goal is practical: Haxe authors should be able to build serious OCaml
applications, compilers, plugins, and developer tools without giving up the OCaml
ecosystem or native-code performance.

That does not mean pretending that Haxe has OCaml's complete module and type
systems. It means providing a typed direct path for the common case, a small typed
OCaml adapter for advanced cases, and a clear error when neither path can preserve
the native contract safely.

“Full ecosystem access” does not mean checking a handwritten wrapper for every
opam package into this repository. It means that the standard path can bind a
representable package on demand, guide an advanced package through a typed
adapter, reproduce the dependency, and keep the boundary reviewable. Everything
needed to build and extend `hxhx` and its native plugins is the first mandatory
coverage set; the same machinery must remain general enough for other packages.

## What Works Today

The current target already provides two useful starting points:

- Portable Haxe code can use the supported Haxe standard-library surface and
  compile to OCaml. Haxe behavior remains the contract.
- OCaml-specific code can opt into the current `ocaml.*` modules, including
  `List`, `Option`, `Result`, `Ref`, `Array`, `Bytes`, `Buffer`, `Char`,
  `Hashtbl`, `Seq`, and the provided map and set specializations.

Typed `@:native` declarations, OCaml labelled arguments, and optional labelled
arguments can describe additional native calls. However, the complete external
package workflow is not ready yet. In particular, the target does not yet ship a
stable command that imports an arbitrary `.mli`, locks the owning opam/Dune
dependency, writes reviewed Haxe bindings, and keeps them updated. Handwritten
native source units and curated public OCaml exports likewise remain planned
workflows.

The distinction matters: being able to spell a native call is not the same as
having a reproducible, typed, package-safe integration.

## Keep Haxe And OCaml Semantics Separate

There are two first-class public surfaces:

```text
portable Haxe API                         target-native OCaml API
-----------------                        -----------------------
haxe.ds.Map, haxe.io.Bytes, Sys          ocaml.Hashtbl, ocaml.Bytes, ocaml.Ref
Haxe 4.3.7 behavior                      OCaml behavior
usable across supported Haxe targets     intentionally OCaml-specific
```

A Haxe standard-library implementation may call an OCaml primitive internally
when the behavior is equivalent. That does not turn the portable API into an
`ocaml.*` API. When nullability, indexing, mutation, exceptions, encoding,
identity, or another observable rule differs, the target must add a small
Haxe-semantics adapter or use another representation.

Conversely, `ocaml.*` should expose the native operation directly when Haxe can
describe it honestly. It should not add a compatibility runtime merely to make
an OCaml API look like a portable Haxe API.

## The Capability Ladder

Use the first level that can preserve the real contract. The compiler must not
silently fall to a weaker level.

1. **Ordinary Haxe or compiler-owned direct lowering.** Use this for portable
   Haxe behavior and for exact target operations the compiler can prove.
2. **Exact `ocaml.*` facade.** A typed Haxe declaration maps one-to-one to an
   OCaml module, value, function, labelled argument, or native carrier.
3. **Haxe-friendly wrapper.** Normal Haxe code wraps the exact facade when a
   clearer name, `Result`, option type, validation rule, or repeated conversion
   materially improves the calling experience.
4. **Generated binding.** A typed importer reads a representable OCaml
   interface and generates completion-friendly Haxe declarations.
5. **Typed `.ml`/`.mli` adapter.** A small OCaml unit turns an advanced native
   API into a first-order interface Haxe can represent safely.
6. **Scoped raw injection.** This is an explicit experimental last resort, not
   an automatic fallback and never part of the `metal` profile.

For example, an ordinary function from an external package should normally be a
direct binding. A generative functor or a GADT may need a small OCaml adapter
that exposes only the concrete operations the Haxe program needs. The generator
must not replace the difficult type with `Dynamic` and call the result safe.

## What Can Be Generated Directly

The planned typed importer should preserve these common OCaml interface forms:

- values and ordinary functions;
- labelled and optional arguments, including the difference between an omitted
  optional argument and a supplied `None`;
- tuples, records, and closed variants;
- ordinary exceptions with representable payloads;
- aliases and opaque nominal types;
- callbacks with a declared arity;
- first-order generic types and functions; and
- stable nested module names through a deterministic Haxe name map.

These forms normally require an adapter, a deliberately narrower API, or a
clear rejection:

- functors, especially generative functors;
- GADTs, existential values, and locally abstract types;
- higher-rank functions and first-class modules;
- module constraints with path-dependent equalities;
- open polymorphic variants with non-trivial row constraints;
- effect handlers or callbacks whose lifetime cannot be enforced in Haxe; and
- compiler-internal APIs tied to one exact OCaml compiler build.

An opaque Haxe handle is acceptable only when construction and decomposition
remain inside a checked OCaml boundary. `Dynamic`, untyped `Obj.t`, and
`Obj.magic` are not general solutions for an interface the importer cannot
model.

## How A Library Will Be “Haxified”

The finished workflow should separate discovery from file changes:

1. **Resolve.** Read the project's actual opam/Dune dependency graph and record
   the package, version or revision, source digest, OCaml toolchain, platform,
   and Dune library name.
2. **Inspect without writing.** Read typed `.mli`, `.cmi`, or `.cmti` data and
   report every supported, adapter-required, and rejected declaration. Do not
   load arbitrary package code merely to discover its API.
3. **Review.** Show the proposed Haxe names, exact native names, type mapping,
   omissions, and reasons before creating files.
4. **Write explicitly.** Generate owned Haxe bindings and a versioned manifest
   only after the author requests a write.
5. **Check.** Compile the Haxe surface, compile the generated OCaml call sites,
   and run one small behavior test against the real package.
6. **Update safely.** Re-run discovery when the package or toolchain changes,
   show a semantic diff, reject collisions with handwritten files, and remove
   stale generated declarations deterministically.

Generated bindings should be *precise or omitted*. If a declaration cannot be
represented safely, the report should explain why and recommend a typed adapter.
It must not quietly widen the signature.

The eventual authoring commands are owned by the reflaxe.ocaml tooling work.
Their final names are not frozen yet, so this page describes the required
behavior rather than advertising commands that do not exist.

## Package And Source Ownership

Every native dependency or source unit entering a build needs structured,
inspectable ownership. At minimum, the record includes:

- opam package and resolved source identity;
- Dune library name and link mode;
- supported OCaml, platform, and profile range;
- source path and digest for local or generated `.ml`/`.mli` units;
- generated Haxe name map and binding-generator version;
- owner and visibility;
- license and redistribution facts; and
- the supported, adapted, and rejected interface inventory.

Dune and opam files should be rendered from this model. Free-form build strings
are a temporary low-level mechanism, not the long-term package contract.
External libraries, user adapters, the Haxe compatibility runtime, and generated
public export wrappers remain separate categories.

## What We Reuse From Other Reflaxe Targets

The sibling targets provide useful patterns without defining OCaml's design:

- **haxe.ruby:** keep the exact target facade separate from Haxe standard-library
  semantics; share a typed native operation only where behavior really matches;
  inventory ownership and test both native behavior and emitted shape.
- **haxe.elixir.codex:** discover first and write second; generate a signature
  precisely or omit it with a reason; let the native package manager keep
  dependency ownership.
- **haxe.rust:** allow small typed native helper islands for resource or lifetime
  behavior Haxe cannot express, but keep those helpers manifest-owned and do not
  let them become a second compatibility runtime.
- **haxe.go:** use deterministic typed interface discovery, stable output, and
  an explicit report for every type-mapping gap; maintain an ownership map for
  Haxe source, runtime support, and exact compiler intrinsics.

For reflaxe.ocaml, the stronger stable rule is that an unsupported generated
binding is adapter-required or rejected. It does not become `Dynamic` merely to
increase coverage.

## Evidence Needed For The Product Claim

Before this project claims broad practical OCaml-ecosystem access, the evidence
must include:

- a complete API-level inventory of the applicable Haxe 4.3.7 standard library,
  with behavior tests and no unsupported or unknown runtime rows hidden by a
  count of target override files;
- the OCaml `Stdlib`, compiler-libs, and supporting package facilities required
  by the declared `hxhx`, compiler-plugin, and target-development workloads,
  exposed through exact facades, generated bindings, or checked adapters and
  recorded in a coverage inventory;
- one ordinary external opam package through generated bindings;
- one advanced package or compiler-libs surface through a small typed adapter;
- positive and negative interface fixtures, including deterministic rejection;
- a Haxe-authored library consumed by an independent OCaml project through a
  curated `.mli`;
- the same target-core decision and behavior through stock Haxe and `hxhx`;
- clean-environment dependency, lock, digest, and package reproduction; and
- generated-code quality and performance comparison with a semantics-matched
  direct OCaml implementation.

`hxhx` is an important downstream QA and compiler-scale workload, but it should
run at selected high-risk, scheduled, and release checkpoints rather than on
every binding edit. Focused binding, adapter, native compile, and runtime tests
must keep the ordinary development loop fast.

## Tooling And Performance Contract

The Haxe-authored workflow is intended to be easier to iterate on than a manual
collection of OCaml build scripts. The binding and adapter tools therefore need:

- read-only discovery by default;
- cache keys that include the interface, package, toolchain, configuration, and
  generator identities;
- affected-unit regeneration rather than whole-project rewriting;
- focused incremental Dune builds and tests;
- inspection that explains bindings, omissions, native dependencies, adapters,
  runtime needs, unsafe operations, and public exports; and
- separate timing for discovery, Haxe generation, OCaml typechecking/compile,
  linking, plugin loading, startup, and workload execution.

A native binary is not automatically a fast workflow. Cold, warm, one-file, and
compiler-server paths must be measured, and regressions need a named owner.

## Work Ownership

The accepted architecture and safety rules live in
[`ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md`](../00-project/ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md).
Implementation is split deliberately:

- `haxe_ocaml-v8a9b`: typed imports, adapters, and native dependencies;
- `haxe_ocaml-1hd2w`: authoring, discovery, inspection, update, and packaging
  commands;
- `haxe_ocaml-7sgtj`: curated OCaml-facing exports;
- `haxe_ocaml-taef5`: one typed call and conversion contract; and
- M22: one target core and compatible plugin payload across stock Haxe and
  `hxhx`.

This page documents the destination. It does not turn the currently planned
binding, adapter, export, or cross-host workflows into supported features.
