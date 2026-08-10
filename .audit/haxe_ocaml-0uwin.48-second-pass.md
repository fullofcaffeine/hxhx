# Catch-chain runtime-use second pass

## Outcome

The planned Haxe catch path now owns the two private OCaml runtime names it
prints: the pattern that receives a Haxe exception and the helper that rethrows
an unmatched exception. The review found no second semantic catch path, output
repair, or broader readiness claim in this change.

## Pattern traversal

`PRuntimeConstructor` keeps a checked runtime-reference token inside the OCaml
pattern tree. The shared AST mapper and walker visit both the constructor and
its child patterns. The printer emits the token's exact symbol using the same
constructor-formatting helper as an ordinary pattern. Runtime-module discovery
and pattern-name collection also handle the new node.

The AST fixture constructs the token through the production authority, visits
it through the exhaustive traversal, collects its runtime module, and checks
the exact printed bytes. The focused catch fixture additionally proves that an
ordinary unchecked `PConstructor("HxRuntime.Hx_exception", ...)` is rejected.

## Catch identity and requirements

The runtime-use plan is derived from a validated `OcamlCatchChainDecision`.
That existing decision identifies the final typed catch, owning function,
program, function-body revision, target pipeline, input channels, and unmatched
behavior. The companion plan adds one exact `HxRuntime` requirement and two
ordered, single-use occurrences:

1. `HxRuntime.Hx_exception` in the pattern domain;
2. `HxRuntime.hx_throw_typed` in the expression domain.

Focused negative cases reject a missing occurrence, changed owner, absent
requirement, stale plan, wrong symbol, wrong domain, and unsupported profile.
The real 13-chain tracer confirms that each reported catch decision publishes
one matching runtime requirement.

## Local and final cardinality

The local check intentionally reconciles a two-use catch fragment, not the
whole catch body. A catch body may contain checked runtime names owned by call,
array, nested-catch, or other lowering plans, so making one catch authority
claim the complete body would confuse independent owners. The small fragment
still proves the exact pattern-before-rethrow order and one-use cardinality.

After that local check passes, the request-wide authority registers the two
occurrences and walks the complete final output tree. Missing or duplicated
output therefore fails even if a checked node is removed or copied after local
lowering. The copy path gives both expression and pattern references new output
identities, and the focused fixture exercises a complete original-plus-copy
tree. A deliberately corrupted final pattern owner is rejected before
printing. Existing final-authority tests continue to cover missing, duplicate,
order, symbol, profile, and unplanned-expression failures.

## Claim boundary

Only the planned catch-chain construction sites moved behind checked runtime
ownership. The private-reference inventory fell from 385 to 383 entries: one
planned pattern and one planned rethrow left the legacy list. The legacy catch
path, private return and loop signals, catch predicates, Map carriers, runtime
source-selection policy, and README Goals are unchanged.

The package-wide null-safety wrapper did not finish within a 12-minute bounded
checkpoint. Direct authority, checked-generated-text, and type-registry
fixtures pass, and the same null-safety traversal is a known pre-existing
tooling defect owned by `haxe_ocaml-tqv34`; no pass is claimed for that wrapper.
