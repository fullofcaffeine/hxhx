# Second-pass review: first occurrence-authorized runtime reference

## Practical result under review

One ordinary `Array<Int>` assignment now proves, before OCaml text is printed,
that its `HxArray.set` call came from the sealed assignment plan. Here,
"sealed" means the compiler has already fixed the assignment's receiver, index,
right-hand side, store, result, runtime requirement, and evaluation order.

This is intentionally one tracer bullet. The other 444 directly generated
private-runtime references remain in the frozen migration inventory and do not
gain authority from this result.

## Independent behavior source

The pinned Haxe 4.3.7 place-evaluation fixture remains the behavior oracle for
receiver, index, right-hand-side, store, and assigned-value ordering. It passed
across the interpreter, JavaScript, and Neko routes. The existing portable
fixtures then proved that the OCaml target still compiles, builds, runs, and
returns the assigned value.

## Architecture review

- The typed array-assignment planner creates exactly one runtime-use occurrence
  for the store. It names the exact requirement and direct `HxArray` runtime
  root selected by the existing requirement ledger.
- A runtime requirement answers "why is this helper needed?" The new occurrence
  answers the narrower question "where may this exact helper name appear?"
  Keeping those records separate avoids turning module selection into proof of
  individual generated calls.
- The target AST gains one restricted expression-identifier constructor, not a
  general expression annotation. Its token carries only use ID, plan revision,
  domain, and exact symbol; it carries no Haxe expression or lowering policy.
- The request-local authority checks the active profile and exact requirement,
  records construction, scans the completed store subtree, and seals itself.
  The printer merely writes the saved symbol.
- The U1/U2 test proves the reason for occurrence identity: valid U1/U2 and
  corrupted U2/U2 contain the same printed helper name twice, but the latter
  fails with duplicate U2 and missing U1.

## Challenge findings and disposition

The first production draft reconciled the entire emitted assignment expression.
That was too broad: a nested array assignment has its own sealed occurrence and
would look unknown to the outer one-use authority. The final implementation
returns both the completed assignment and its exact store-call subtree, then
reconciles only that owned subtree. This preserves independent nested plans
without allowing an unknown token inside the store call.

The authority is not yet a function-wide composition layer. Generated text,
patterns, types, raw OCaml, and the remaining expression families are still
owned by their follow-up Beads. Runtime source selection also remains separate.
No README goal or readiness claim changes.

## Review conclusion

The implementation matches the accepted Oracle architecture for the first
bounded slice: semantic meaning stays in the Haxe-authored plan, provenance
survives in structured target syntax, and final checking happens before the
printer. The xhigh level was sufficient. Another Oracle call is unnecessary
because the parent architecture review already selected this exact tracer and
the second pass found and corrected the only composition hazard before closure.
