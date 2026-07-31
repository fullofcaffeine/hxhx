# Temporary Bridge Boundaries

This page explains the four narrow adapters that `hxhx` still carries while its
native compiler path matures. It also records the retired handwritten
lexer/parser bridge so future work does not accidentally recreate a second
frontend.

A **bridge** is a temporary adapter between two parts of the compiler that do
not yet connect cleanly. A bridge is not automatically a bug, and removing one
too early can break working behavior. The important rules are:

1. keep each bridge in a small, named set of files;
2. test the behavior it protects;
3. do not copy the workaround into new code; and
4. remove it only after the replacement path passes the named exit evidence.

The machine-readable companion is
`docs/00-project/BOOTSTRAP_BRIDGE_INVENTORY.json`. Run
`npm run guard:bridge-boundaries` after changing any file listed below.

This inventory covers temporary Haxe-side and socket bridges. The broader
handwritten-OCaml rule, including target runtime modules, native ABI adapters,
generated artifacts, and the excluded Stage3 semantic shims, is documented in
`docs/00-project/HANDWRITTEN_OCAML_OWNERSHIP.md` and enforced by
`npm run guard:handwritten-ocaml-ownership`.

## Quick map

| Bridge | What problem it solves today | Where it may appear | What lets us remove it |
| --- | --- | --- | --- |
| Backend method adapter | Native OCaml output can lose enough interface information that a custom backend's `emit` method cannot always be called normally. | `BackendDispatchBoundary.hx` implements the fallback; `Stage3EmitSupport.hx` is its only caller. | Builtin and real plugin backends call the typed `IBackend.emit` path in native output, with no reflective fallback, while focused and Full1 plugin tests pass. |
| Backend input type recovery | Native backend dispatch can expose an already-typed program as an opaque runtime value. | `GenIrBoundary.hx`, its one Stage3 input call, and the JS/OCaml target-core checks. | The backend-facing program type crosses native interface calls without recovery casts in JS, OCaml, and one source/native target. |
| Compiler-driver OCaml hint | The OCaml compiler sometimes needs an explicit reference before it recognizes a generated record field's defining module. | One `untyped __ocaml__` expression in `CompilerDriver.hx`. | A current-source native build and `--hxhx-selftest` pass after removing the hint, including the generic and record-label cases it protects. |
| Compiler-server socket helper | Current native output cannot yet use the relevant `sys.net.Socket` input/output access reliably. | `NativeCompilerServer.hx` and the two calls in `Stage3WaitServer.hx`. | Native `sys.net.Socket` supports the same wait/connect lifecycle and errors, and the existing socket roundtrip passes without the helper. |

## 1. Backend method adapter

Plain-language behavior: Stage3 asks the selected backend to generate target
code. Known built-in backends use normal typed calls. A custom backend may use
one reflective fallback in the native Reflaxe path because its interface method
table can be missing there.

- Long-lived owners: Full1 plugin outcome `haxe_ocaml-gskz9` and promotion
  product `haxe_ocaml-bomhr`.
- Allowed Haxe files:
  - `packages/hxhx-core/src/backend/BackendDispatchBoundary.hx`
  - `packages/hxhx/src/hxhx/Stage3EmitSupport.hx`
- Focused proof today:
  - `npm run test:m14:backend-dispatch-boundary`
  - `npm run guard:bridge-boundaries`
- Exit evidence:
  - a custom plugin backend and a builtin target both use typed dispatch in a
    native build;
  - the reflective branch is not reached;
  - the focused dispatch test and the authentic Full1 plugin workload pass.

## 2. Backend input type recovery

Plain-language behavior: `GenIrProgram` names the program value that backends
receive. Today it is still the compiler's macro-expanded typed program. It is
**not** a normalized, target-neutral intermediate representation (IR).

The boundary helpers recover that known type when native interface dispatch
temporarily presents it as an opaque value.

- Long-lived owners: Full1 compiler closure `haxe.ocaml-f1cl` and promotion
  product `haxe_ocaml-bomhr`.
- Allowed Haxe files:
  - `packages/hxhx-core/src/backend/GenIrBoundary.hx`
  - `packages/hxhx/src/hxhx/Stage3EmitSupport.hx`
  - `packages/hxhx-core/src/backend/js/JsTargetCore.hx`
  - `packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx`
- Focused proof today:
  - `npm run test:m14:backend-dispatch-boundary`
  - `npm run test:m14:target-core-wiring`
  - `npm run test:m14:js-target-core-wiring`
  - `npm run guard:bridge-boundaries`
- Exit evidence:
  - generated native code preserves the backend input type across the interface;
  - JS, OCaml, and at least one source/native target pass without the recovery
    calls;
  - no new general IR is introduced unless two or more backends first prove a
    shared, behavior-tested transformation.

## 3. Compiler-driver OCaml hint

Plain-language behavior: one zero-cost OCaml reference helps the generated
compiler see the module that owns `ResolvedModule.getParsed` before it accesses
the associated record data. This is a bootstrap accommodation, not an API for
embedding arbitrary OCaml in compiler code.

- Long-lived owners: Full1 compiler closure `haxe.ocaml-f1cl` and the native
  `hxhx + reflaxe.ocaml` product `haxe_ocaml-38gsp`.
- Allowed Haxe file:
  - `packages/hxhx-core/src/CompilerDriver.hx`
- Focused proof today:
  - `npm run guard:bridge-boundaries`
  - a native `hxhx --hxhx-selftest` run from the bootstrap/current-source
    validation lane.
- Exit evidence:
  - remove the hint in a candidate change;
  - build a current-source native `hxhx` from clean inputs;
  - run `--hxhx-selftest` and the generic/record-label bootstrap cases;
  - keep the change only if those checks pass without generated-source patching.

## 4. Compiler-server socket helper

Plain-language behavior: `--wait host:port` keeps a compiler server running,
and `--connect host:port` sends it a compile request. Stage3 owns the request
format. A small OCaml runtime module currently owns only the unreliable socket
transport operations.

- Long-lived owner: native incremental-server product
  `haxe_ocaml-850ii.32`. The completed cache-free transport foundation
  `haxe_ocaml-850ii.32.1` proved that the OCaml module is socket-only.
- Allowed Haxe files:
  - `packages/hxhx/src/hxhx/NativeCompilerServer.hx`
  - `packages/hxhx/src/hxhx/Stage3WaitServer.hx`
- Hand-written runtime source:
  - `packages/reflaxe.ocaml/std/runtime/HxHxCompilerServer.ml`
- Focused proof today:
  - the `Stage3 regression: --wait socket + --connect roundtrip` section of
    `npm run test:hxhx-targets`;
  - `npm run guard:bridge-boundaries`.
- Exit evidence:
  - a pure-Haxe `sys.net.Socket` transport passes the same roundtrip;
  - lifecycle, framing, connection failure, and shutdown behavior stay the same;
  - a native trace shows that `HxHxCompilerServer` is no longer linked or called.

## Retired: handwritten native lexer/parser

Early bootstrap builds used handwritten OCaml lexer/parser modules because the
Haxe-authored parser could not yet process representative compiler input. By
July 2026 that exception had become a second semantic frontend: the same Haxe
source could be interpreted differently depending on a build define or
environment flag.

The concrete failure was
`cast haxe.SysTools.winMetaCharacters`. The OCaml path joined two tokens into
`casthaxe`, hid a startup dependency, and generated JavaScript that crashed
before `main()`. The Haxe path preserved the expression. This was not merely a
protocol bug; it proved that two parsers created two competing meanings for one
source program.

`haxe_ocaml-e1kqo` therefore hard-cut parsing to `HxParser`. The retirement
removed the OCaml modules, Haxe externs, wire decoder, selection flags, runtime
manifest rows, bootstrap patching, and protocol-only tests. Generated
bootstrap snapshots are regenerated from the Haxe source rather than edited by
hand.

The durable rule is simple: valid Haxe syntax that the compiler cannot parse is
now a Haxe-parser parity bug. Fix it in the Haxe-authored frontend and prove it
against upstream Haxe 4.3.7 behavior. Do not restore a target-native semantic
parser, not even as an apparently temporary fast path.

## Changing a boundary

If a new use really is necessary:

1. first create or update a bead that explains the user-visible problem;
2. add a focused test that fails without the new use;
3. explain why the existing boundary cannot own it;
4. update the JSON inventory and guard together; and
5. record the new exit evidence.

Do not add a path merely to silence the guard. A new allowed path is an
architecture change and should be easy for a reviewer to notice.

`BRIDGE_RETIREMENT_INVENTORY:PASS` means the four adapters are still confined
to their approved files and their retirement records are complete. It does not
mean the bridges have been removed, or that Full1 compatibility is complete.
