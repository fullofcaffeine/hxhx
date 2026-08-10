# Final runtime-use reconciliation design

## Problem

A local runtime-use check can prove that one lowering plan produced its one
authorized OCaml helper expression. It cannot prove how many times that same
expression is later placed in the complete generated program. Reusing the
already-checked expression twice therefore turns one permission into two
output occurrences.

## Boundary

Keep local checks, then add a request-owned final ledger. A local authority may
register its immutable occurrence facts only after its own expression or
generated-text check succeeds. Immediately before a structured module is
printed, the ledger walks that final module tree and counts the hidden runtime
reference identities. Checked generated text is counted from its sealed hidden
references immediately before its exact bytes are written.

At the end of private output assembly, before publication, the ledger requires
the final count and owner-local order to match the union of locally accepted
plans. Rendered OCaml names remain a consistency signal, never permission.

The ledger counts only hidden references that already carry authority. Plain
private names from still-unmigrated compiler sites remain visible in the
machine-checked migration inventory. Rejecting them here by name would confuse
an incomplete migration with a completed authority contract.

## Stop conditions

Stop and redesign if the check requires parsing rendered OCaml, retaining Haxe
compiler objects, moving semantic decisions into the printer, or creating
process-global state that can survive one compiler request.
