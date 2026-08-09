# Second-pass review: Bytes access runtime uses

Bead: `haxe_ocaml-0uwin.35`

Review date: 2026-08-09

## Practical result

Exact `haxe.io.Bytes` reads and writes no longer gain permission to call a
private OCaml helper merely because syntax knows its name. The completed access
decision now lists every permitted conversion helper, followed by the final
selected `HxBytes` operation. Syntax must consume that list exactly before
generated OCaml is printed.

For an access with two nullable multi-byte inputs, the order is:

1. convert argument 0 through `HxBytes.requireMultiByteInt`;
2. convert argument 1 through `HxBytes.requireMultiByteInt`;
3. run the selected final `HxBytes` read or write.

The two conversions share one semantic HxBytes requirement but have different
use identities and argument roles. A single-byte nullable conversion instead
uses a separate HxRuntime requirement for
`HxRuntime.nullable_int_unwrap`.

## Identity and ownership review

- The access decision remains the only owner of bounds, width, endian order,
  carriers, conversion policy, mutation, aliasing, result shape, and final
  operation.
- Runtime requirement identities are derived after the access identity is
  complete, so no circular identity dependency was introduced.
- Each helper occurrence binds the function, program, typed-body, and target
  pipeline revisions through one plan revision. It also records owner,
  requirement, exact symbol, argument-specific role, source span, profile,
  order, and cardinality.
- `OcamlBytesAccessSyntax` creates private helpers only as checked runtime
  identifiers. It returns the identifiers it inserted separately from the
  complete expression, so nested receiver and argument work remains owned by
  its own compiler decisions.
- The builder checks the identifier sequence before printing. The generic
  authority also rejects direct unmarked calls to every migrated Bytes access
  operation.
- Int64 constructor and field adaptation remain under the existing exact Int64
  representation decision; this task did not claim them as HxBytes runtime
  helpers.

The added records are request-local plain values. No Haxe compiler expression,
mutable compiler context, builder, printer, or output writer was added to a
persistent cache.

## Adversarial and vertical evidence

- The behavior-first test was red for the intended missing-field reason after
  the Haxe 4.3.7 oracle passed.
- Missing and wrong-symbol use records fail.
- Reversing two conversion calls and the final access fails.
- Plain direct calls to every migrated HxBytes access helper fail.
- Single-byte nullable, multi-byte nullable, two-conversion, Float, Int64,
  BytesData alias, and static fast-get plans pass.
- Generated OCaml compiles, builds with Dune, and runs through the M6 Bytes
  integration path.
- Runtime requirement, public inspection, inventory, and formatting gates pass.

## Scope and disposition

The migration inventory fell from 422 to 419 entries, removing exactly the
three `bytes-access-syntax` rows. Other Bytes families and the remaining 419
entries are unchanged. Requirements-only source selection is still shadow work,
and README readiness does not move.

Disposition: the bounded design is fail-closed and the selected
`thinking:xhigh` level was sufficient. The second pass added two-conversion
coverage but found no need for an Oracle escalation or architecture change.
