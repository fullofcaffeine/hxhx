The existing `OcamlCatchChainDecision` already fixes the source try node,
function/body/pipeline revisions, ordered catch clauses, input channels, and
unmatched behavior. A companion runtime-use plan should derive from those facts
and add one `HxRuntime` requirement plus two ordered occurrences.

Use an expression occurrence for `HxRuntime.hx_throw_typed` and a pattern
occurrence for `HxRuntime.Hx_exception`. Add a restricted pattern constructor
that carries `OcamlRuntimeReference` in the target AST, prints the same OCaml
bytes, and is visited by shared AST traversal. Extend request-local authority
with checked pattern construction, and make both request-local and final-output
reconciliation inspect pattern provenance and reject a plain copy of either
planned symbol.

The builder creates one authority from the exact chain and current function
binding, then constructs the fallback and pattern through it. The local check
uses a small structured catch fragment that contains only those two owned uses,
because catch bodies can contain private references owned by other plans. The
request-wide final check still walks the complete returned `try` expression and
proves that the same two hidden IDs reached output exactly once. No string scan,
generated-output repair, handwritten OCaml, broad builder permission, or second
exception implementation is allowed.

Start with an independently authored focused expectation that fails because
the companion plan and checked pattern node do not exist. Preserve the
regression, then prove the existing real catch fixture against installed Haxe
4.3.7. Stop and redesign if the sealed chain cannot uniquely own both uses, if
pattern traversal loses provenance, or if final reconciliation needs to trust
rendered OCaml.
