# Second-pass review: nullable primitive field defaults

## Decision

Proceed. The change binds each generated `Null<Int>` or `Null<Bool>` field
default to a concrete field or static-storage owner, and the reviewed evidence
does not show a route that can reuse the permission for another generated
value. This closes one migration row only; runtime source selection and product
readiness remain incomplete.

## Ownership and identity

- The production caller already supplies a stable owner for every declaration:
  instance fields use the class/field initializer identity plus the emission
  role, while static fields use the sealed static-storage initialization
  identity and revision.
- The new plan revision includes that owner, its revision, the source span, the
  exact representation ID/revision/domain/type, the runtime requirement, the
  profile inventory, and the exact target symbol.
- The representation decision remains a carrier fact. A carrier-only query can
  return `Obj.t` without creating a plan, authority, requirement occurrence, or
  target identifier.

## Multiplicity and generated output

The normal constructor and the compiler-generated empty constructor can both
contain the same field default. The request-local plan first authorizes one
source occurrence. The existing final-output authority then gives a deliberate
constructor copy its own hidden output identity before publication. The
instance-field tracer generated both `holder_create` and `holder___empty`, and
the complete output reconciliation passed without weakening cardinality.

Static fields use their own declaration/storage identities. The static tracer
proved same-module and separate-module storage, and both target builds produced
the same lowering report before the executable ran.

## Requirement scope

Only exact `Null<Int>` and `Null<Bool>` decisions in the instance-field or
static-field domains produce the new requirement. Internal values, mutable
locals, captured locals, array elements, exact primitives, and other nullable
families do not receive it. Each vertical report contains exactly two new
requirements, rooted only at `HxRuntime`, with the matching representation as
the cause.

The requirement says field storage starts at Haxe null before an explicit
initializer runs. This covers both omitted and explicit field initializers and
avoids overstating the behavior as an omitted-field-only rule.

## Fail-closed checks

Focused checks reject missing plan/authority, duplicate construction, stale
revision, wrong owner, wrong symbol, wrong profile, wrong domain, corrupted
carrier/default facts, and a plain copy of the plan's own private symbol. The
plain-name check is scoped to the current sealed plan because other
`HxRuntime.hx_null` migration rows still exist; globally reserving that symbol
now would incorrectly claim that those unrelated rows were already migrated.

## Evidence and limitations

- The focused representation test was red for the missing plan type and
  materializer contract, then passed after implementation.
- The runtime-requirement fixture, inventory guard, no-`Dynamic` guard,
  mega-file guard, touched-file formatting, complete Haxe formatting, shell
  syntax, and diff checks pass.
- The instance and static portable fixtures each compile generated OCaml twice,
  compare deterministic lowering reports, build and run the native executable,
  compare behavior, and inspect the generated carrier/default shape and runtime
  requirements.
- The static tracer also runs installed Haxe 4.3.7 as an independent behavior
  oracle. It compares nullable defaults and every mutation/result, excluding
  only the fixture's separately documented non-null primitive defaults and
  whole-number float formatting differences.
- The legacy inventory moved from 386 to 385 and lost only the
  `field-representation-materializer` entry.
- The aggregate runtime-use authority command was not counted as evidence. Its
  package-wide null-safety setup again exceeded the bounded checkpoint and left
  a child after the wrapper ended; only that owned process group was stopped.
  Existing Bead `haxe_ocaml-tqv34` owns making that guard bounded.

Oracle was deliberately skipped. The Haxe 4.3.7 behavior, existing field owner
seam, focused corruption matrix, final-output authority, and two real native
tracers provide a bounded local proof. Escalation is still appropriate if the
later requirements-only hard cut fails to converge.

`thinking:xhigh` was sufficient: the second pass found and corrected the
overloaded six-argument helper API and the explicit-initializer wording before
closure, without requiring broader architecture work.
