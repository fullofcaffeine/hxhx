# Forwarding constrained generic parameters

A caller may forward a type parameter when its own declared bounds prove the
callee's requirements. The proof must retain the caller's exact parameter identity.
Matching source names alone supply no evidence.

Run `haxe test/m14_generic_forwarding_constraint_test.hxml` from the repository root.
The test checks upstream acceptance for every source case. Positive cases also
compare generated JavaScript in Node and inspect the selected call and result type.
The test index loads the real standard-library `Class` declaration.

- `object`: a differently named caller parameter retains its object bound.
- `transitive`: related caller parameters prove both an object and another parameter.
- `class_argument`: a `Class<B>` argument preserves the relation between `A` and `B`.
- `nullable`: a nullable argument retains its declared object guarantee.
- `dynamic`: the existing declared `Dynamic` input rule remains available.
- `nominal`: an inherited class and interface satisfy a compound bound.
- `unconstrained`: a same-spelled parameter with no bound must reject.
- `scalar`: an integer bound cannot prove an object bound.
- `shadowed_bound`: a concrete class cannot replace an unrelated same-spelled parameter.

Separate proof tests check that cycles terminate, independent evidence remains
available beside a cycle, and foreign parameter identities cannot borrow bounds.
