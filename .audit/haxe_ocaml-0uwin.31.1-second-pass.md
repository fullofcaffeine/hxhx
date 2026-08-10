# Second-pass review: nullable IMap storage-alias runtime ownership

Outcome: accepted after one versioning correction. Nullable standard-Map aliases now carry one exact `HxRuntime` requirement and two ordered private-name permissions. Non-null aliases carry neither. Generated behavior is unchanged.

The review challenged the important failure cases:

- A missing, reordered, wrong-symbol, or wrong-requirement occurrence is rejected by the shared IMap contract before syntax.
- Syntax receives only the requirements named by this exact alias and reconciles only the two names it inserts; the source expression keeps its own authority.
- Saved-report inspection revalidates both occurrence facts and the matching requirement, and rejects an unreferenced or edited requirement.
- The real String-, Int-, and object-key nullable fixtures still evaluate the field once, throw catchable `Null Access`, build native OCaml, and produce the expected runtime output.
- The negative and ordinary IMap fixtures prove this permission does not spread to non-null aliases, user implementations, or ordinary source-level Map-to-IMap conversions.

The initial draft advanced the storage proof ID. That was unnecessary because the behavioral claim did not change. The final design advances only the IMap evidence model from v5 to v6 and retains `typed-standard-map-storage-alias-v2`.

Oracle was not used. The semantic behavior was already fixed by the accepted nullable-Map contract and executable fixture; the implementation boundary was the existing sealed alias decision, so an external architecture review would not have added a missing decision.

This closes two legacy private-name sites. It does not complete requirements-only runtime selection, move README readiness, or authorize any other runtime family.
