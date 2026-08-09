# Second-pass design review: nullable standard Map storage aliases

## Outcome

Keep the implementation. It closes one exact boundary without turning every
nullable reference or every `IMap` value into raw OCaml Map storage.

The source pattern is a compiler-generated local whose declared Haxe type is
`haxe.Constraints.IMap<K,V>`. Its initializer is an exact static
`Null<Map<K,V>>` field. The target may preserve the raw `HxMap` carrier only
because two earlier plans prove both the static field's `Obj.t` storage and the
local's closed set of target-owned `NativeHxMap` uses.

## What callers can rely on

For this admitted pattern, generated code:

1. evaluates the static field read once;
2. checks the stored `Obj.t` value with `HxRuntime.is_null`;
3. raises a catchable Haxe `Null Access` value when it is null; and
4. otherwise uses checked `Obj.obj` to recover the exact standard Map carrier.

The syntax builder does not rediscover these facts. It consumes a sealed plan
that records the source semantic type, source carrier, target carrier, key
kind, null policy, exact function identity, and approved use inventory.

## Safety review

The second pass checked the believable ways this could be wrong:

- An arbitrary `Null<Map<K,V>>` local is not admitted. The initializer must be
  an exact static field read with a matching sealed static-storage entry.
- A user-defined `IMap` implementation still uses the checked interface
  dispatch record. It is never treated as `HxMap` storage.
- An ordinary non-null standard Map alias keeps its previous raw carrier and
  records `non-null-source`; the new null check is not inserted there.
- A candidate that is assigned, captured, returned, compared, passed to an
  unrelated function, or dispatched through public `IMap` methods cannot use
  the raw-storage alias.
- Wrong source carrier, target carrier, key kind, null policy, function
  identity, or pipeline revision fails before generated output is accepted.
- The admitted conversion uses `Obj.obj` only after the exact carrier proof and
  null check. It does not use `Obj.magic` as conversion evidence.
- Existing unrelated `Obj.magic` uses elsewhere in generated compiler output
  remain outside this claim; this task does not relabel them as safe.

## Evidence

The focused fixture is independently anchored to stock Haxe 4.3.7. Eval,
Neko, and Python throw on the tested null operation, while JavaScript returns
null. The OCaml target deliberately chooses the fail-closed throwing behavior
and keeps the JavaScript difference visible rather than claiming one universal
cross-target result.

Focused String-, Int-, and object-key cases compile generated OCaml and run.
The non-null storage-alias, rejected-alias, and user-implementation fixtures
also pass. Inspection rejects edited carrier and null-policy evidence, and six
semantic reports were regenerated twice with identical bytes.

The complete portable portfolio reports 102 of 105 fixtures passing. The new
nullable Map fixture and all adjacent Map/IMap fixtures pass. A detached run of
the parent commit reproduces the same three failures in
`haxe_core_bucket02_basic`, `null_bool_local_truthiness`, and
`null_int_local_conversions`; they are pre-existing local-conversion gaps, not
regressions introduced here. They remain visible rather than being reported as
green.

The compiler-scale current-source run passed the former nullable Map failure
and reached a later missing local assignment conversion at
`EmitterStage.hx:7778`. That advancement closes this task's acceptance gate but
does not claim that the complete compiler build passes.

## Review level and Oracle decision

`thinking:xhigh` was necessary because a wrong carrier choice could generate
believable but invalid OCaml. It was sufficient because the final boundary is
small, has an independent behavior oracle, has exact positive and negative
fixtures, and fails before output when its evidence is missing. No competing
architecture remains, so an additional Oracle review was deliberately not
requested for this slice.

README Goals remain unchanged. This is one internal semantic-safety advance,
not a new supported route or a 1.0 readiness claim.
