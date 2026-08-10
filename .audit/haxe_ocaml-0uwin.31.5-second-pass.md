# Second-pass review: sealed Float catch admission

## Outcome

This slice is safe to commit. A typed `catch (value:Float)` now receives the
same pre-syntax catch decision as the already supported exact value families.
The decision fixes the OCaml `float` carrier, the program-owned
`representation:Float:internal-value`, the exact runtime tag `Float`, and
exact-value recovery before the target builder sees the catch.

The real tracer now reports 14 sealed application catch chains instead of 13,
and generated OCaml builds and runs with the expected Float result. The private
runtime inventory remains at 380 because this task does not yet remove the old
catch implementation needed by the remaining class and enum blockers.

## Challenges and dispositions

### Does the control planner invent a second Float representation?

No. It calls the existing representation registry for the exact Float type and
the internal-value domain. Validation requires the resulting `float` carrier
and `representation:Float:internal-value` identity. The focused negative test
changes only the carrier to `int` and confirms that construction fails.

### Can another numeric type enter the Float catch accidentally?

No. Source lookup reconnects the decision only when the fresh typed catch
variable is exactly Float. The clause uses the exact `Float` runtime tag rather
than numeric coercion. Int remains a separate exact tag and carrier.

### Does adding Float change source catch order or Dynamic fallback?

No. Float is another exact tagged clause. The existing chain validation still
requires every clause's source order and still permits a match-all Dynamic
clause only in the final position. The focused fixture places Float between
other exact clauses; the real tracer gives the Bool and Float tries separate
owner identities.

### Are completed and non-completing branches treated correctly?

Yes. The vertical run exposed that the Float try body is a throw and therefore
keeps a polymorphic target result, while its completed assignment catch body is
discarded in statement position. The test now asserts this exact pair instead
of copying the neighboring Bool try's two discard policies.

### Can stale plans or reports be reused after this semantic expansion?

No. The function-plan pipeline advances to v85. The catch proof/model advances
to v4, the enclosing control model to v22, and the lowering schema to 70.
Public inspection and all active fixture consumers require those identities.
The six checked-in lowering goldens were regenerated through the repository's
two-run determinism mode, which compares both generated reports before
replacing a golden.

### Is expected behavior independent of the implementation?

Yes. The pinned Haxe 4.3.7 exact-catch oracle passes three execution routes and
12 cases. The OCaml vertical fixture separately compiles, builds, runs, checks
the exact Float decision, repeats generation, invokes public inspection, and
rejects corrupted saved evidence.

### Why was the legacy catch compiler not deleted?

The initial task inspection found five other live blocked catches: four
standard-library `haxe.io.Eof` chains and one `haxe.io.Error` enum chain. The
first is a generated class carrier and the second a native enum carrier. The
old route must not be deleted until those types have sealed decisions, and it
must not be granted new authority merely to reduce an inventory count.
Successor `haxe_ocaml-0uwin.31.6` owns those representations and the hard cut.

## Verification and limitation

Focused control planning, Float corruption, runtime requirements, exact-catch
Haxe 4.3.7 oracle, native OCaml build/run, deterministic public report,
inspection/corruption, six report-golden regeneration checks, private-runtime
inventory, Haxe formatting, no-`Dynamic`, local-path, and diff checks pass.

The general `npm run test:reflaxe-ocaml:inspect` portfolio is red for a separate
nullable static-field default requirement that it does not mark as referenced.
The exact-catch inspection used by this task is green, and the broader failure
is recorded as `haxe_ocaml-0uwin.49`; this task does not weaken the final
unreferenced-requirement check.

Oracle review was deliberately skipped. The representation owner, behavior
oracle, version boundary, and safe bounded implementation were all explicit.
No unresolved architecture choice or non-convergent debugging remained.

README readiness and runtime source-selection authority do not move from this
slice.
