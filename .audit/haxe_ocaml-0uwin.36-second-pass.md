# Second-pass review: Bytes read runtime uses

Bead: `haxe_ocaml-0uwin.36`

Review date: 2026-08-09

Reason: `thinking:xhigh` changes require a separate design and evidence pass
before closure.

## Practical result

Read-only `haxe.io.Bytes` calls no longer gain access to private OCaml helpers
merely because target syntax knows their names. The completed compiler decision
now lists every permitted helper. Syntax must consume the exact list before any
OCaml source can be printed.

A normal non-null read owns one final call such as `HxBytes.length`. A read on
`Null<Bytes>` owns this order:

1. `HxRuntime.is_null` checks the receiver value that was evaluated once;
2. `HxRuntime.hx_throw_typed` provides the existing typed `Null Access` branch;
3. the selected `HxBytes` operation runs only after the receiver conversion and
   source-ordered arguments have completed.

`Obj.repr` remains an ordinary OCaml standard-library adapter. It is not part
of the project-owned private runtime and therefore does not receive a private
runtime-use record.

## Identity and ownership review

- The Bytes read decision owns the declaration, receiver conversion, argument
  schedule, result representation, and function/program/body/pipeline
  revisions.
- Each private-name occurrence records one exact requirement, symbol, role,
  source span, supported profile set, order, and cardinality.
- The requirement ledger separately explains why all reads need `HxBytes` and
  why only nullable-receiver reads also need `HxRuntime`.
- `OcamlBytesReadSyntax` receives request-local authority and returns only the
  helper identifiers it inserted. Helpers in nested receiver or argument
  expressions remain owned by their own compiler decisions.
- `OcamlRuntimeUseAuthority` checks identity, requirement root, profile,
  ordering, and cardinality before printing.

The planner uses a short request-local `Dynamic` assembly step because the
final runtime-use IDs depend on the already-computed decision ID while the
public decision fields are immutable. This does not widen the decision API or
reach target syntax: the value is immediately cast back to the closed decision
shape and fully validated. It follows the same bounded assembly pattern already
used by the neighboring Bytes mutation and access decisions.

No Haxe compiler expression, compiler context, builder, output writer, or other
request-owned mutable host object was added to persistent state.

## Adversarial checks

- Missing and duplicate helper records fail.
- A wrong `HxBytes` name fails.
- A stale plan revision fails.
- A narrowed or wrong profile set fails.
- Reversing nullable check, throw, and final-read records fails.
- Corrupting the receiver conversion or its representation fails.
- Plain `HxBytes.length`, `sub`, `compare`, `getString`, `toString`, and `toHex`
  references fail, as do plain `HxRuntime.is_null` and
  `HxRuntime.hx_throw_typed` references.
- The independent Haxe 4.3.7 behavior oracle still proves receiver-first
  evaluation and null failure before argument side effects.
- The real Bytes integration compiles Haxe to OCaml, checks the generated
  receiver conversion, validates the runtime-requirement report, builds with
  Dune, and runs the executable.

## Scope and disposition

The private-runtime migration inventory fell from 419 to 416 entries, removing
exactly the three constructors formerly owned by Bytes read syntax. The other
416 entries remain unresolved. README readiness, runtime source-selection
authority, and other Bytes operation families do not move.

The broad runtime-authority verification exposed a separate tooling problem:
cold macro fixtures took roughly 9–14 minutes apiece despite passing. That
latency is not treated as normal product speed, but it does not weaken this
change's correctness evidence or justify changing test topology inside this
bounded semantic task.

Disposition: the design is fail-closed and the selected `thinking:xhigh` level
was sufficient. No Oracle escalation is needed because the existing sealed
decision and runtime-use authority supplied a bounded, previously reviewed
implementation seam.
