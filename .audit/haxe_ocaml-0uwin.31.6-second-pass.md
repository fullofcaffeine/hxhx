# Second-pass review: sealed catch hard cut

## Outcome

The change now has one semantic owner for every supported Haxe catch. The typed
planner records clause order, matching, payload recovery, private control-flow
protection, and unmatched behavior. `OcamlBuilder` only turns that checked plan
into OCaml syntax; it no longer contains a second implementation that makes the
same decisions again.

This review used repository tests and the exact Haxe 4.3.7 behavior oracle. It
did not use GPT-5.6 Pro Oracle because the accepted Bead already named the seam,
the implementation stayed within that seam, and each risk had a focused local
test. Oracle remains appropriate if later catch types cannot be represented
without changing the whole-program type model.

## Risks challenged

### Could target syntax invent an enum or class representation?

No. `haxe.io.Error` uses the existing ordinary-enum carrier identity and its
sealed runtime tag. `haxe.io.Eof` is admitted through the same monomorphic class
planner as application classes and carries the planner's module, target type,
layout digest, and proof identity. Focused tests corrupt each carrier/layout and
require rejection before code generation or by public report inspection.

### Could an unsupported catch silently use the removed implementation?

No. Function sealing inspects the complete catch-admission snapshot. Any
blocked non-empty catch is a compiler error before syntax. A negative compile
uses a valid generic Haxe exception, verifies the hard-cut diagnostic, and
checks that the failed request did not replace the valid lowering report.

### Could the runtime package omit support used only while binding a catch?

The first implementation had this gap for `HxEnum.unbox_or_obj`: the tracer's
typed enum throws independently selected `HxEnum`, so its successful build did
not prove a catch-only program. The corrected model gives each sealed enum
clause its own `haxe-enum-catch-payload-recovery-v1` requirement. A focused
catch-only ledger test and the real fixture both check that reason.

### Could an old plan or report be accepted under the new meaning?

No. Root function plans moved to `v86`; the lowering report moved to schema 71;
the control model moved to v23; and the catch-chain/proof models moved to v5.
All checked-in consumers were updated, six deterministic report fixtures were
regenerated through the compiler, and a second regeneration produced identical
hashes.

### Did the hard cut change supported behavior?

The exact Haxe 4.3.7 oracle still passes all 12 cases. The portable fixture
builds and runs native OCaml with 19 sealed chains, including four standard
library `haxe.io.Eof` catches and one `haxe.io.Error` catch. Source order,
primitive catches, Haxe wrapper catches, Dynamic fallback, private control
propagation, native exceptions, `Void` result handling, and value-producing
catches remain covered.

## Remaining boundary

Generic exception classes still have no sealed catch representation and now
fail clearly. That is intentional: this hard cut removes silent fallback; it
does not claim support for every future catch type. Adding one requires a new
typed representation decision and focused behavior evidence rather than syntax
guessing.
