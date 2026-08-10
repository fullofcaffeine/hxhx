# Second-pass review: direct Array bracket reads

## Outcome under review

A direct read such as `makeValues()[makeIndex()]` now receives one sealed
compiler decision before OCaml syntax is built. That decision permits exactly
one private runtime call, `HxArray.get`. It also fixes the evaluation order as
receiver, index, then read.

This slice does not authorize Array writes, compound assignments, increments,
decrements, string-key anonymous access, Bytes access, or Array methods.

## Challenges and dispositions

- **Could an assignment or update target become a read as well as a write?**
  No. The planner excludes the target root for assignment, compound assignment,
  increment, and decrement. It still visits the receiver and index because
  those child expressions can contain independent value reads. The focused
  fixture checks both target families.
- **Could syntax use a decision from another request or function?** No. Each
  decision includes the function, program, body, and target-pipeline revisions.
  The plan rejects a stale binding and maps an active typed node to one decision.
- **Could a type that only resembles `Array<T>` enter this path?** No. Admission
  follows the final typed receiver to the built-in root `Array` class, requires
  an exact `Int` index, and requires the expression result to match the element
  type. Other numeric bracket reads now fail closed at the former legacy site.
- **Could the receiver or index run twice or in the wrong order?** No. Syntax
  stores the receiver in one temporary, then stores the index in one temporary,
  and finally calls `HxArray.get`. A real Haxe and native OCaml comparison checks
  the observed order `receiver,index` and the returned value.
- **Could the runtime name be invented directly by syntax?** No. The builder
  asks `OcamlRuntimeUseAuthority` for the exact symbol bound to the decision. It
  reconciles the introduced identifier and rejects a missing, duplicate, stale,
  wrong-owner, wrong-profile, wrong-order, or plain private reference.
- **Do nested and standalone expressions retain the same rule?** Yes. Root,
  nested-function, and standalone plans each carry their own Array-read plan.
  Builder state saves and restores it at each boundary.
- **Did the change hide generated-output repair or handwritten OCaml semantics?**
  No. The implementation is Haxe-authored. Generated OCaml is only inspected and
  executed. The handwritten-OCaml ownership guard passes.
- **Did evidence grow beyond the implementation?** The function-plan revision
  changed because the sealed input changed. Inspection validators and the six
  semantic report goldens were updated through their normal deterministic
  generator. Validation was not weakened.
- **Is the readiness claim broader now?** No. The private-reference inventory
  decreases by exactly one entry. README goals and product-readiness claims stay
  unchanged.

## Residual scope

The plan is intentionally conservative. Unsupported or uncertain bracket reads
are compile-time failures until another typed family owns them. Selective report
presentation for Array-read decisions can be added later if a report consumer
needs it; the runtime requirement, use occurrence, focused fixture, inventory,
and executable tracer already own this slice's acceptance.
