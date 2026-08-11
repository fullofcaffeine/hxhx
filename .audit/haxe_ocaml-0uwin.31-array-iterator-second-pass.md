# Array iterator runtime-use second pass

## Result

The design is sound for this bounded migration family after two corrections.
The parent runtime-authority program must stay open because 323 legacy
references remain.

## Checks and corrections

1. Type traversal is complete for the new checked type nodes. The printer,
   tree traversal, static-storage copy, type ordering, runtime module
   collector, local authority, and final authority all handle
   `TRuntimeIdent` and `TRuntimeApp`.
2. Final output now checks private type names in both expression annotations
   and module type declarations. The focused authority fixture fails without
   this observation and passes with it.
3. A root plan now stops at a nested function. The nested function has a
   different body revision and receives its own plan. The focused iterator
   fixture includes a nested stored method that must not increase the root
   decision count.
4. Direct and stored `Array.iterator` forms create the generated
   `haxe.iterators.ArrayIterator` class. They do not claim private
   `HxIterator` authority. The vertical fixture proves item order and one
   receiver evaluation for both forms.
5. Only an exact `Array<T>` to `Iterable<T>` boundary authorizes
   `HxIterator.of_array`. Only a structural `Iterator<T>` literal authorizes
   the `HxIterator.t` carrier.
6. Local reconciliation and final-output reconciliation both require one use
   for each private reference. Missing, duplicate, stale, wrong-domain,
   wrong-symbol, wrong-profile, and plain private names fail.
7. The six large lowering-golden diffs contain the same semantic data after
   plan IDs and revision hashes are removed. The plan revision changes those
   hashes and their sort order. All six real fixtures passed.
8. The change does not generalize to arbitrary iterators, maps, a second
   target IR, generated-file repair, or handwritten OCaml compiler logic.

## Evidence

- Full portable portfolio: 113 of 113 fixtures passed before the two
  second-pass corrections.
- Focused runtime-use authority: passed after both corrections.
- Focused Array iterator plan: passed after the nested-function correction.
- Structural iterator vertical fixture: compiled, built, ran, and passed its
  inspection tamper checks after both corrections.
- Runtime requirement fixture: passed.
- Runtime inventory guard: passed with 323 entries. Only the two
  `builder-iterator` entries were removed.

The focused post-correction tests own the corrected behavior. Repeating the
entire portable portfolio would add substantial time without testing a wider
changed boundary.
