# Second-pass review: anonymous-object runtime authority

## Practical result

Ordinary anonymous objects keep the behavior they already had, but the OCaml
target can no longer insert their private helper calls from unchecked strings.
For example, `{enabled: false}` owns one exact `HxAnon.set` use and one exact
`HxRuntime.box_bool` use. A later field operation cannot borrow either
permission, and both must appear once in the planned target-tree order.

This does not complete runtime source selection. The frozen migration inventory
still contains 408 private references owned by other compiler families, so the
aggregate hard cut and README readiness remain unchanged.

## Semantic owner and scope

The Haxe-authored anonymous-structure plan remains the semantic owner. It fixes
the admitted object shape, field carriers, object identity and alias behavior,
evaluation schedule, conversions, operation, source occurrence, and enclosing
function/program/body/pipeline revisions. Syntax translates those completed
facts; it does not recover types or expand the admitted shape.

No handwritten OCaml module gained compiler decisions. `HxAnon`, `HxRuntime`,
and `HxInt` still perform only the primitive operations that the Haxe plan
selected.

## Exact private names and ordering

Each create, initializer, read, write, or admitted `Int +=` operation now owns
its exact private identifiers:

- create: `HxAnon.create`;
- initializer/write: `HxAnon.set`, followed by `HxRuntime.box_bool` when the
  field uses the Boolean carrier;
- read: `HxRuntime.unbox_bool_or_obj` when needed, then its nested
  `HxAnon.get`;
- admitted `Int +=`: `HxAnon.get`, `HxInt.add`, then `HxAnon.set`.

This order follows a pre-order walk of the operation-owned target expression.
Receiver and assigned-value expressions remain owned by their own plans, so an
outer object operation cannot claim private helpers introduced by nested source
expressions.

Literal creation uses a separate request-local authority for the allocation and
for every source-ordered initializer. The builder checks both directions: every
returned runtime subtree must have an authority, and every created authority
must return exactly one subtree for reconciliation. This prevents a field from
reusing a sibling's permission or silently leaving an authority unchecked.

## Requirements, reports, and failure closure

Every occurrence points to a requirement with the same direct runtime root.
Boolean conversion now has its own `HxRuntime` requirement instead of relying
on the broader `HxAnon` module requirement. The lowering report and public
inspection preserve and revalidate these identities.

Focused tests reject missing, duplicated, reordered, stale, wrong-symbol,
wrong-profile, and plain private references before printing. The real fixture
also reverses a report's runtime-use inventory and proves that public inspection
rejects it with the anonymous-operation contract error.

## State and transaction review

Authorities are request-local and contain only immutable strings, source spans,
requirement facts, and occurrence facts. They retain no `TypedExpr`, compiler
context, builder, output writer, or process-global cache. Reconciliation seals
an authority after its single operation. Output publication, Dune execution,
and runtime-source selection keep their existing owners and commit points.

## Evidence and independent oracle

- The behavior-first test was red for the intended reason: anonymous operation
  decisions had no `runtimeUseOccurrences` field.
- The focused planner fixture proves deterministic identities and all corruption
  cases, including the outer Boolean-unbox/nested-field-read order.
- The `anon_struct_basic` tracer compiles Haxe to OCaml, builds with Dune, runs
  the native executable, and compares it with stock JavaScript, Neko, and eval.
  It covers source-order initializers, aliases, Boolean reads/writes, `Int +=`,
  signed 32-bit overflow, deterministic reports, and corrupt-report rejection.
- Runtime-requirement, direct authority, inventory, formatting, shell syntax,
  and diff checks pass.

## Tooling finding and disposition

The package-wide authority command again spent more than nine minutes in the
unrelated full-package null-safety macro before reaching its small fixture. The
previous slice already stack-confirmed this same defect after 34 minutes 51
seconds. I stopped the owned session and ran the direct authority fixture, which
passed immediately. The latency remains owned by `haxe_ocaml-850ii.23`; it is
not normalized as acceptable edit-loop speed.

The implementation is narrow, fail-closed, and follows an already accepted
runtime-use model. A new Oracle review would add little because there is no
remaining competing architecture, provenance question, or unclear ownership
boundary in this slice.
