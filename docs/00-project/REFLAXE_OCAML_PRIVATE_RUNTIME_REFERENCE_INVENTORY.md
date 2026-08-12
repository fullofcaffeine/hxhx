# Private OCaml runtime-reference migration inventory

## What this protects

The OCaml target still contains direct Haxe-source constructors for internal
helpers such as `HxArray.set`, plus a few compiler-generated text and raw OCaml
boundaries. Those sites are not automatically wrong, but the current compiler
usually remembers only the module name after target syntax is built. For
example, two distinct planned calls to `HxArray.set` look the same once both
have been reduced to the module name `HxArray`.

The machine-readable inventory freezes that legacy surface while occurrence-
level authority is implemented. In everyday terms, **occurrence-level
authority** means the compiler can connect each concrete generated helper use
to the exact earlier plan that required it, rather than accepting any use from
a module that was needed somewhere else.

Files:

- `REFLAXE_OCAML_PRIVATE_RUNTIME_REFERENCE_INVENTORY.json` is the committed
  snapshot;
- `scripts/ci/reflaxe-ocaml-runtime-reference-inventory.js` discovers and
  compares the current source; and
- `scripts/ci/reflaxe-ocaml-runtime-reference-inventory-fixture-test.js` proves
  deterministic discovery and the no-growth failure.

## Current baseline

The current reviewed baseline contains 232 legacy entries:

| Domain | Entries | What it means |
| --- | ---: | --- |
| Structured expressions | 232 | Direct `EIdent` or `EField(EIdent)` construction of a private runtime symbol. |
| Structured patterns | 0 | Private runtime pattern constructors now use checked occurrence authority. |
| Generated text | 0 | Generated files now use checked placeholders instead of private names hidden in ordinary text. |
| Raw boundary | 0 | `__ocaml__` now reaches the target AST only through a validated injection value; the guard still detects any new unchecked `ERaw...` variant. |

All 232 entries are in `OcamlBuilder.hx`. That is an ownership warning, not a
reason to place each migration there. Each semantic family should move through
a focused lowering or syntax module. New runtime-reference infrastructure must
remain small and independent of that large builder.

Direct calls to the standard Haxe `Reflect` class now use sealed runtime-use
decisions. Dynamic call behavior remains a separate call-boundary concern; it
must not be counted as direct `Reflect` authority.

Typed String `==` and `!=` expressions also use sealed runtime-use decisions.
The plan records one `HxString.equals` use and left-to-right evaluation for
each expression. Null-literal and `Dynamic` comparisons keep their separate
behavior. The executable fixture proves equal, unequal, nullable, nested, and
standalone cases.

Direct standard String method calls now use a separate sealed plan. It covers
`toUpperCase`, `toLowerCase`, `charAt`, `charCodeAt`, `indexOf`, `lastIndexOf`,
`split`, `substr`, `substring`, and `toString`. The plan distinguishes an
omitted optional index from an explicit `null` and from a computed nullable
integer. It also binds the receiver once before it evaluates arguments. The
portable executable fixture compares results with upstream Haxe and checks
that receiver and argument side effects occur once in source order.

Direct reads of the standard `String.length` field also use a sealed plan. The
plan accepts only the root `String` field with a `String` receiver and `Int`
result. It records one checked `HxString.length` use and evaluates the receiver
once. The portable fixture proves local, standalone, nested, and side-effecting
receivers against upstream Haxe.

Typed `Reflect.compare` String comparators now own two null checks. The builder
binds each result once, then applies the sealed exact-String or nullable-String
ordering policy. Its existing real OCaml fixture checks the results against the
independent Haxe 4.3.7 oracle.

Static `String` and `Null<String>` conversions now own every
`HxString.toStdString` use. This includes `Std.string`, concatenation,
String `+=`, and String field names passed to `Reflect`. The plan is separate
from Dynamic conversion because its OCaml input carrier is a typed `string`,
not `Obj.t`. The portable fixture also found and fixed right-to-left target
evaluation. It now proves Haxe's left-to-right operand order against upstream
Haxe 4.3.7.

These String changes reduce the earlier 252-entry baseline by 20 entries. They
do not change the readiness bar while 232 unchecked sites remain.

## What the guard does not prove

This inventory reads the Haxe implementation. It does not prove why a helper is
needed, and it never makes generated OCaml text the source of truth. It is a
temporary migration map and a no-growth guard.

The later correctness path is:

```text
Haxe behavior needs a helper
  -> sealed lowered plan records one use
  -> checked target identifier consumes that use
  -> final structured syntax contains it exactly once
  -> runtime manifest supplies the directly required module
```

The inventory must reach zero before the runtime report can say authority is
complete. Compiler-observed module names and output scans may remain negative
consistency checks, but they cannot authorize a use.

## Reviewing a change

Run the focused proof first:

```bash
npm run guard:reflaxe-ocaml-runtime-reference-inventory
```

A new direct reference fails with its source file, line, domain, constructor,
and target symbol. A removed or changed entry also fails because the committed
snapshot must be reviewed explicitly.

After confirming that a tracked Bead owns the addition, removal, or migration,
regenerate with that Bead ID:

```bash
node scripts/ci/reflaxe-ocaml-runtime-reference-inventory.js \
  --write \
  --review-bead haxe_ocaml-EXAMPLE
```

Then inspect the JSON diff. Do not refresh it merely to make CI green. A new
entry needs a concrete reason and migration owner; a removed entry needs the
focused occurrence-authority and compile/build/run evidence for its semantic
family.

This inventory changes no generated program behavior, runtime selection,
release status, or README progress by itself.
