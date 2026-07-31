# Handwritten OCaml Ownership

The compiler now has one enforceable rule: **Haxe decides what the source
program means; handwritten OCaml performs only an already-selected target,
operating-system, ABI, or toolchain operation.**

This prevents a small bootstrap helper from quietly becoming a second compiler.
The immediate audit removed the unused legacy `HxHxMacroRpc` client, classified
all remaining production `.ml` files, and quarantined three Stage3 shims that
cannot count toward product readiness.

The machine-readable source of truth is
`docs/00-project/HANDWRITTEN_OCAML_OWNERSHIP.json`. Run:

```bash
npm run guard:handwritten-ocaml-ownership
```

The guard fails when a new handwritten `.ml` or `.mli` file lacks an ownership
class, a runtime file bypasses the locked runtime manifest, an OCaml adapter
contains placeholder `Obj.magic 0` success, a retired bridge returns, or a
Stage3 shim is presented as supported architecture.

## The smallest useful mental model

Good boundary:

```text
Haxe source
  → Haxe parser, resolver, typer, and lowering choose a known operation
  → a typed Haxe extern names one narrow native primitive
  → OCaml performs the selected runtime/OS/ABI action
  → Haxe validates the result and owns compiler-visible failure
```

Wrong boundary:

```text
Haxe source or incomplete generated output
  → handwritten OCaml guesses what the compiler meant
  → the OCaml helper repairs, retypes, lowers, or returns a placeholder
  → later tests see plausible output from a second semantic implementation
```

A **semantic decision** is a choice that changes program behavior: how tokens
form an expression, which declaration a name resolves to, which modules must
be invalidated, which runtime operation a typed call requires, or whether an
unsupported construct fails. Those decisions belong to Haxe.

A **native primitive** is an operation whose meaning has already been selected
and whose implementation is naturally target-specific: opening a socket,
spawning a process, loading a `.cmxs`, registering an OCaml callback, hashing
bytes, or representing a checked runtime value.

## Current ownership

| Class | Current files | Why it exists | Readiness treatment |
| --- | ---: | --- | --- |
| Generated OCaml artifacts | Bootstrap snapshots and test goldens | Reproducible output from Haxe-authored source or the target printer | Never hand-edit; regenerate and review |
| Application runtime modules | 25 manifest-locked modules | Implement runtime capabilities already selected by Haxe lowering or compiler policy | Source integrity is proven; semantic completeness remains owned by `haxe_ocaml-0uwin` |
| Tooling native adapters | 5 manifest-locked modules | Socket I/O, OCaml dynlink, and callback registration | Allowed only behind the listed Haxe request/ABI validators and focused lifecycle tests |
| Temporary Stage3 semantic shims | `Haxe_Int64.ml`, `HxBootArray.ml`, `HxBootProcess.ml` | Keep the independent Stage3 OCaml emitter usable during migration | Explicitly excluded from product and Full1 evidence; retire through `haxe_ocaml-38gsp.1` |
| Native adapter fixtures | 2 test-only modules | Exercise the socket and dynlink boundaries in real OCaml | Test evidence only |

The exact module names, Haxe owners, Beads, tests, and removal evidence live in
the JSON inventory. The locked runtime manifest separately owns every runtime
source digest, dependency, profile, Dune library, and license.

## Why runtime modules may remain OCaml

“Keep compiler semantics Haxe-authored” does not mean every byte linked into an
OCaml executable must originate as Haxe.

For example, Haxe lowering can decide that a checked standard-output operation
needs `HxStdio`. The runtime module may then call OCaml's channel APIs. The
compiler decision—when standard output is needed, which typed Haxe declaration
requested it, which profile permits it, and what failure means—remains in Haxe.
The OCaml file implements the selected target operation.

The boundary becomes invalid if the runtime scans generated text to guess
whether it is needed, chooses a different Haxe meaning, silently substitutes a
value, or repairs malformed target output. `haxe_ocaml-0uwin` is closing the
remaining gap by making every runtime requirement semantic and fail-closed
before packaging.

## Temporary Stage3 shims are not runtime architecture

The three files under `packages/hxhx-core/shims/` support the independent
Stage3 emitter:

- `Haxe_Int64.ml` supplies a separate Stage3 integer carrier and operation set.
- `HxBootArray.ml` dynamically recovers arrays and deliberately converts poison
  values so bootstrap runs can reach the next diagnostic.
- `HxBootProcess.ml` implements a separate process model and currently returns
  placeholder values for the `stdout` and `stderr` object accessors.

These files are useful diagnostic debt, but they demonstrate why a green
Stage3 workload is not evidence for the final shared target. The hard-cut Bead
`haxe_ocaml-38gsp.1` must route native `hxhx` through the actual standalone
`reflaxe.ocaml` target core. That cut removes the independent emitter's need for
these shims rather than promoting them into a second runtime.

## Retired during this audit

The handwritten `HxHxNativeLexer` and `HxHxNativeParser` were removed by
`haxe_ocaml-e1kqo.2` after the Haxe parser became authoritative.

This follow-up audit also removed `HxHxMacroRpc.ml` and its Haxe extern. The
file implemented a complete legacy macro-host protocol client in OCaml, but
production code had already moved to the Haxe-authored `MacroHostClient` using
the checked process runtime. Keeping the old bridge would have preserved a
second, unused protocol implementation with no product owner.

The remaining macro and backend-plugin OCaml modules are narrower: they call
OCaml `Dynlink` or retain callback registrations. Haxe owns manifest selection,
snapshot decoding, ABI validation, macro/backend selection, request cleanup,
and failure behavior.

## Adding or changing an OCaml boundary

Before adding or materially expanding a handwritten production `.ml`/`.mli`
file:

1. show the typed Haxe owner that selects the operation;
2. name the exact runtime, OS, ABI, or toolchain primitive OCaml provides;
3. explain why the Haxe/native target path cannot yet express that primitive
   safely;
4. add the module to the locked runtime manifest or the temporary-shim
   inventory, including its Bead, lifecycle, tests, readiness treatment, and
   removal evidence;
5. add a focused behavior test and a negative/failure test; and
6. run the ownership, bridge, runtime-manifest, and relevant behavior guards.

If the proposed OCaml code needs to parse Haxe, recover a missing typed fact,
choose invalidation or lowering behavior, patch generated files, or make an
unsupported case appear successful, stop. The missing behavior belongs in the
Haxe compiler or in an explicitly selected, fail-closed target runtime
capability.

`HANDWRITTEN_OCAML_OWNERSHIP:PASS` means every current handwritten OCaml source
is visible and classified. It does not mean the Stage3 shims are acceptable
product architecture, every runtime module has complete Haxe 4.3.7 parity, or
the shared target hard cut is finished.
