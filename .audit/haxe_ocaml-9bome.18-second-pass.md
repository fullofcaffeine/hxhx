# Second-pass review: stable IMap conversion identities

## Outcome

The fix is safe to close. An unchanged Haxe program now produces the same IMap
conversion identities even when an unrelated compiler edit changes temporary
variable allocation. The implementation changes saved evidence, not the
runtime meaning of an IMap conversion.

## Boundary review

- Local initializer conversions use the existing `LexicalLocalIdentityPlan`.
  This plan names a local from its owning function and source structure. The
  compiler may still use Haxe's temporary `TVar.id` to find that local during
  one request, but the number is never published or hashed into reusable
  evidence.
- Nested functions use the same complete lexical identity plan as their
  enclosing sealing pass. That plan already walks nested bodies and gives each
  nested local a distinct owner path, so the target does not invent a second
  identity scheme for closures.
- Other conversion roles do not need a lexical-local identity. Call arguments
  use `call-argument:<index>`, while return and assignment conversions use the
  fixed names `return-value` and `assignment`.
- The report reader validates these exact shapes. A numeric local identity is
  rejected even if someone recomputes the surrounding report hash.

## Revision and golden review

The IMap model, complete lowering-report schema, and root/nested function-plan
revisions were all advanced. This is a hard cut: old evidence is rejected
instead of being interpreted under the new identity contract.

Six deterministic lowering goldens changed because the report schema and
derived identities changed. They were generated twice. Numeric inventories and
the canonical IMap semantic sets stayed equal after removing identity and
revision bookkeeping, so the refresh did not hide a target-behavior change.

## Evidence sensitivity

Before the fix, adding one unused, behavior-preserving local binding in an
unrelated OCaml printer changed two published local role numbers, their
conversion IDs, derived runtime-requirement IDs, the IMap aggregate revision,
and the complete report digest. After the fix, repeating the same perturbation
produced byte-identical reports with SHA-256
`06096df5a6a70b59bf16177ff77ead47ff36a80d734f4f1dc6f9be03f809c0f8`.

The public inspector also received a negative test that replaces a stable local
identity with the old numeric form and recomputes the aggregate revision. It
rejects that report, proving the check is about the identity contract rather
than only a stale checksum.

## Verification

- standalone runtime-requirement ledger fixture: pass;
- public report inspector fixture: pass;
- focused nullable, alias, standard-runtime, and user-IMap fixtures: pass;
- full portable portfolio: 107 of 107 pass;
- changed Haxe formatting, shell/JavaScript syntax, local-path, handwritten
  OCaml ownership, and whitespace guards: pass.

Oracle review was deliberately skipped. The repository already has one
accepted generic lexical-local identity boundary, and the red reproduction
isolated a bounded misuse of a temporary host ID. There was no competing
architecture or unclear semantic seam requiring external review.

README goals and readiness percentages remain unchanged. This fix makes target
evidence reproducible; it does not complete a new product scenario.
