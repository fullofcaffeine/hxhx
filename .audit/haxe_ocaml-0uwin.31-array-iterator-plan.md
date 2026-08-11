# Authorize standard Array iterator runtime references

## User-visible outcome

`Array.iterator()` and a stored `array.iterator` method produce the standard
Haxe `ArrayIterator` class. They preserve the values and evaluate the Array
receiver once. When an Array crosses an `Iterable<T>` boundary, the target
proves which exact typed argument authorizes the private `HxIterator.of_array`
adapter. A structural `Iterator<T>` object literal separately authorizes its
private `HxIterator.t` carrier type.

## Current gap

The builder has one shared helper that creates `HxIterator.of_array` as a plain
target expression. Structural iterator object literals also create the private
`HxIterator.t` type as plain target syntax. These sites appear in the legacy
runtime-reference inventory, so runtime-use authority is not complete.

The first real compile added an important correction. Haxe 4.3.7 rewrites a
direct `Array.iterator()` call to `new ArrayIterator(...)` before the target
runs. A stored `array.iterator` method is also typed to return `ArrayIterator`.
The old builder returned the structural `HxIterator.t` record from the stored
method. That target value did not match its Haxe type.

## Design boundary

Add one Haxe-authored plan for the exact iterator-producing boundary. The plan
owns the source occurrence, Array element type, output type, source form, and
profile. Direct and stored methods create the standard generated
`ArrayIterator` class and need no private runtime-use permission. Only an exact
Array-to-`Iterable<T>` conversion can authorize `HxIterator.of_array`. Only an
exact structural iterator literal can authorize `HxIterator.t`.

Add a restricted runtime type identifier to `OcamlTypeExpr` and teach the
printer, traversal, final-output copier, and reconciler to preserve and check
it. The type reference carries only occurrence provenance. It must not carry
Haxe type or lowering semantics.

Do not generalize this work to arbitrary iterators, Map adapters, a second
target IR, output-text scanning, or handwritten OCaml compiler semantics.

## Acceptance criteria

1. A focused expected-red test shows that the current Array iterator path has
   no exact runtime-use plan for its expression and carrier type.
2. The direct form follows Haxe 4.3.7 and creates `ArrayIterator`. A stored
   `array.iterator` method returns the same class. Neither form claims a private
   `HxIterator` use. Exact Array-to-`Iterable` and structural-literal decisions
   seal the private expression and type references that they emit.
3. Missing, duplicate, stale, wrong-owner, wrong-symbol, wrong-profile,
   wrong-domain, and plain private type or expression references fail before
   printing.
4. A real Haxe fixture compiles to OCaml, builds, and runs direct and stored
   iterator forms. It proves receiver evaluation once, item order, and
   `hasNext`/`next` behavior against a manually authored expectation.
5. Exactly the `builder-iterator` inventory entries disappear. Unrelated
   inventory and runtime source-selection authority remain visible.
6. Focused authority, iterator, inspection, inventory, format, and relevant
   portable gates pass.
7. An explicit `thinking:xhigh` second pass checks type traversal, final-output
   copying, cardinality, bound-closure ownership, and claim limits.
8. README goals remain unchanged unless this slice supplies a missing
   same-candidate product proof.

## Completion evidence

- The focused expected-red failed because checked private-runtime type names
  did not exist.
- Runtime-use authority, Array iterator planning, runtime requirements, and
  the runtime inventory guard pass.
- The structural iterator fixture compiles authored Haxe, builds generated
  OCaml, runs it, compares the manually authored output, and rejects corrupted
  inspection data.
- The complete portable portfolio passed all 113 fixtures.
- The repository-wide Haxe format guard and Dynamic/untyped boundary guard
  pass.
- The required second pass is recorded in
  `.audit/haxe_ocaml-0uwin.31-array-iterator-second-pass.md`.
- The legacy inventory decreased from 325 to 323. The parent authority Bead
  remains open for the other migration families.
