# Second-pass review: direct array-literal runtime ownership

## Outcome

The change is ready to close after final Beads bookkeeping. A direct represented
`Array<Int>` or `Array<String>` literal now proves, before OCaml text is printed,
that its allocation uses exactly `HxArray.create` and that each source element
uses exactly one ordered `HxArray.push`. Generated program behavior did not
change.

## Invariants reviewed

- The existing Haxe-authored array-literal producer remains the semantic owner.
  It still decides allocation, one evaluation per element, one store per
  element, source order, and the final returned array.
- The runtime-use records are plain immutable values tied to the exact function
  plan, producer identity, source location, profile, symbol, role, order, and
  cardinality.
- Target syntax can create the private `HxArray` identifiers only through a
  request-local authority. Missing, duplicated, reordered, stale, wrong-symbol,
  wrong-profile, and unrestricted plain identifiers fail before rendering.
- Reconciliation checks only the literal-owned create and push expression
  subtrees. Element expressions remain independently owned because they can
  contain calls or nested literals with their own plans.
- Nested-function requirements are recorded only after that nested plan has
  been admitted. An empty literal owns one create use and no push use.
- Runtime packaging gains one exact `haxe-array-literal-construction` reason
  rooted at `HxArray`; no requirements-only source-selection authority was
  enabled.

## Findings and dispositions

1. The first real-program run showed that the lowering report did not yet carry
   producer-owned runtime requirements. The report writer and public inspector
   now validate and retain those requirements.
2. The first string-array check showed that its guard rejected every producer
   runtime-requirement family, including this new legitimate one. The guard now
   admits only the exact array-literal requirement and still rejects unrelated
   expansion.
3. The review found that each literal would sort and copy the full program-wide
   runtime ledger to validate one requirement. The ledger now has an exact-ID
   lookup that fails on missing or repeated IDs. Array literals and the existing
   simple array-assignment path use it, avoiding repeated whole-program work.
4. No semantic or lifecycle blocker remains. The six changed lowering snapshots
   contain the expected model-revision and runtime-ownership additions; they do
   not establish a broader product-readiness claim.

## Evidence

- Focused red state: `npm run test:reflaxe-ocaml:array-literal-producer-plan`
  failed because the decision did not yet contain runtime requirement or use
  records.
- Focused green checks: array-literal producer plans, runtime requirements,
  runtime-use authority, checked generated text, and type-registry generated
  text.
- Real boundaries: `early_return` proved direct integer and string literals,
  including nested literals; `array_string_element_runtime` and
  `place_array_simple_assign` compiled generated OCaml, built it with Dune, and
  ran it successfully.
- Inventory: 426 references remain. Exactly the two `array-literal-syntax`
  entries were removed.
- Repository checks: the Haxe formatter guard, inventory guard, shell/JavaScript
  syntax checks, JSON parsing, and `git diff --check` passed.

## Review escalation

An additional Oracle review was deliberately skipped. This bounded slice
implements the already accepted runtime-use-authority model recorded in
`.audit/haxe_ocaml-0uwin.26-oracle-disposition.md`; the ownership seam is clear,
the corruption matrix is executable, and this written second pass satisfies the
repository requirement for `thinking:xhigh` work. Oracle remains appropriate if
a later family exposes an unclear semantic owner or invalidation boundary.
