# Second-pass review: raw OCaml private-runtime boundary

## Outcome

The change is safe to close after the final gates pass. Portable raw OCaml now
rejects an authored compiler-private name such as `HxRuntime`. Ordinary raw
OCaml remains available, while the metal profile keeps its stronger rule that
rejects raw injection entirely.

An interpolated expression is no longer converted to text early. It remains a
normal OCaml target-syntax child until printing, so existing compiler checks can
still see a planned helper call such as `HxArray.set`.

## Risks challenged

### Could interpolation duplicate or discard a checked helper use?

Yes, in the first draft. A template could repeat `{0}` or omit it after the
argument's semantic checks had run. The final design plans placeholders before
compiling arguments and requires every supplied typed argument exactly once.
Focused tests cover valid, repeated, omitted, and out-of-range placeholders.

### Could two adjacent segments form a private name only after printing?

Yes, in the first draft. For example, authored `H{0}` could join with an
expression that prints an identifier beginning with `x`. The final planner
rejects a placeholder directly adjacent to an authored identifier character.
Focused tests cover text joined on both sides of a placeholder.

### Could the source boundary and generated-text boundary disagree?

The original identifier scanner lived inside the checked generated-text
builder. It is now one small shared Haxe module. Both boundaries therefore use
the same rule: `Hx` followed by an uppercase ASCII letter is compiler-private
when it occurs as OCaml code. Existing tests prove that the same text inside an
OCaml string or nested comment remains data rather than an executable name.

### Did the new AST node become invisible to analysis or inventory tools?

No. The shared AST traversal exposes interpolated expression children. The
printer, runtime-use collector, free-identifier checks, and identifier queries
all handle the new node. The migration inventory now recognizes both `ERaw`
and `ERawInterpolated`; it excludes only the traversal's mechanical rebuild of
an already-authorized node. Its independent fixture protects that exclusion.

### Did a real consumer require a private-runtime placeholder API?

No. A repository-wide Haxe-source inventory found two raw `HxRuntime.hx_null`
uses, both in macro-host end-of-file handling. Each actually needed a typed Haxe
`null`, so both now interpolate `(null : Null<String>)`. A forced-stage0 macro-
host generation and native Dune build passed. No other raw consumer needs a
compiler-private helper, so a new placeholder API remains deliberately
deferred.

## Evidence reviewed

- The expected-red source assertion failed because portable raw
  `HxRuntime.hx_null` compiled successfully before the boundary existed.
- `npm run test:printer` passes the AST traversal, printing, exact-once, and
  joined-token checks.
- `npm run test:reflaxe-ocaml:checked-generated-text` passes the shared scanner,
  checked-placeholder, type-registry, corruption, and clean-repeat checks.
- `npm run test:m6:metal-strict` passes the real portable private-name
  diagnostic, ordinary portable injection, and unchanged metal rejection.
- The `raw_ocaml_interpolation_runtime` portable fixture compiles generated
  OCaml, builds it, runs it, observes `result=7` and `stored=3`, then regenerates
  byte-identical `Main.ml`.
- A forced-stage0 macro-host build completed successfully in a private temporary
  output directory.
- The runtime-reference inventory guard passes with 428 entries and zero
  generated-text entries. The human-readable inventory was corrected from its
  stale pre-migration counts.
- The repository Haxe-format guard and mega-file watch pass.

## Deliberately unchanged

Raw OCaml remains an expert escape hatch in portable mode. This task reserves
the compiler's private runtime namespace; it does not sandbox ordinary OCaml or
turn arbitrary raw code into typed Haxe. README goals and readiness claims do
not change.

The local seam and tests were concrete, so an Oracle review was deliberately
skipped. This written second pass satisfies the `thinking:xhigh` review policy.
