# Second-pass review: Bytes producer runtime authority

## Practical result

Supported ways to create `haxe.io.Bytes` now preserve Haxe's argument behavior
and prove the exact private OCaml helper before any generated source is printed.
For example, `new Bytes(lengthExpression, dataExpression)` evaluates the length
expression first, the data expression second, and each exactly once. The final
call can use only the `HxBytes.create` occurrence recorded by that exact compiler
decision.

This review does not claim that runtime source selection is complete. The frozen
migration inventory still contains 411 private references owned by other
families, so the aggregate hard cut remains open and README readiness is
unchanged.

## Ownership and semantic boundary

The Haxe-authored `OcamlBytesProducerDecision` remains the source of truth. It
chooses the producer kind, construction and aliasing policy, optional encoding,
argument schedule, result representation, runtime requirement, and exact runtime
call. `OcamlBytesProducerSyntax` only turns those completed facts into OCaml
syntax. It cannot classify a Haxe call, select another runtime function, or add a
private identifier without request-local authority.

No handwritten OCaml module gained compiler semantics. The existing `HxBytes`
runtime still performs the already-selected primitive operation.

## Identity and failure closure

Each producer occurrence is bound to the exact function, program, typed body,
target-pipeline revision, source span, decision ID, requirement ID, profile,
symbol, role, order, and cardinality. The plan revision and fingerprint include
the runtime argument mask and the full runtime-use record.

Validation rejects a missing, duplicated, stale, wrong-symbol, wrong-profile,
wrong-role, reordered, or plain private runtime call before printing. The target
builder reconciles only the identifier inserted by the producer. Nested argument
expressions can therefore keep their own runtime-use owners instead of being
incorrectly claimed by the outer producer.

## Evaluation order and compile-time inputs

OCaml does not provide the Haxe source-order guarantee for function arguments.
The syntax helper now creates nested `let` bindings in the sealed source order
and calls `HxBytes` only after those bindings exist. A real `Bytes` program proves
that the generated executable observes length before data.

The optional `Bytes.ofString` encoding has a different contract. Planning admits
only omitted, `null`, `Encoding.UTF8`, or `Encoding.RawNative`, all of which are
compile-time selectors. The decision records that selector but marks it as not a
runtime argument, so syntax neither evaluates it again nor invents a runtime
dependency for it.

## State and transaction review

The new authority is request-local and contains immutable strings, source spans,
and requirement facts. It retains no `TypedExpr`, compiler context, output writer,
or process-global cache. Reconciliation seals the authority after one use. Output
publication and runtime-source selection keep their existing owners and commit
points.

## Evidence and independent oracle

- The first focused run was red for the intended reason after upstream Haxe
  passed: the decision lacked runtime-argument and runtime-use facts.
- The Haxe 4.3.7 interpreter independently proves constructor evaluation order.
- The focused plan fixture covers all five producer kinds and supported encoding
  forms, deterministic replanning, exact requirements, and corrupted decisions.
- The real M6 Bytes fixture compiles generated OCaml, builds it with Dune, runs
  it, and observes the same constructor order and aliasing behavior.
- The direct authority fixture proves plain forms of all five migrated names are
  rejected.
- Runtime requirement, source-selection shadow, inspection, inventory, and Haxe
  formatting checks pass.

## Tooling finding

The packaged authority command spent 34 minutes 51 seconds in the generic
`nullSafety("reflaxe.ocaml")` macro before reaching the fixture. Two process
samples showed the same package-wide `NullSafety` traversal at full CPU with
stable memory. The direct authority fixture passed in about 0.12 seconds without
that unrelated setup. This is a test-topology defect, not an accepted feature
cost, and remains owned by `haxe_ocaml-850ii.23`.

## Review disposition

The implementation is narrow, fail-closed, and consistent with the accepted
runtime-use model. The focused and vertical tests expose the main semantic risk,
and the aggregate source-selection gate remains honestly blocked by the rest of
the inventory. A new Oracle review would add little because no competing
architecture or unresolved ownership boundary remains in this slice.
