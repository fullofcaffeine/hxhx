# Second-pass design review: standard Map storage aliases

## Outcome

Keep ordinary `Map`-to-`IMap` conversion and compiler-generated storage aliases
as two different planned outcomes.

An ordinary conversion creates the checked `IMap` dispatch record. A storage
alias keeps the raw `HxMap` value only when the final typed function proves that
the local exists solely to feed the target standard library's native map
storage operations. Syntax generation may consume this answer, but it may not
recognize or extend the pattern itself.

## Evidence

The Haxe 4.3.7 record dump shows this exact typed shape for a standard
`Map<String, Int>` field operation:

```text
[Var this1(...):haxe.IMap<String, Int>]
    [Field:Map<String, Int>] Main.forwarded
[Call:Void] haxe.ds.NativeHxMap.set_string
    [Cast:HxMap<Int>] [Local this1(...):haxe.IMap<String, Int>]
```

The same shape appears for `exists_string` inside the nested function. The
source-level temporary does not exist; Haxe creates it while expanding the
multi-type `haxe.ds.Map` abstract. The target maps `Map<String,V>` and
`StringMap<V>` to raw `HxMap.string_map` storage, while a genuine `IMap<K,V>`
value uses an opaque checked dispatch record.

The focused static-field fixture fails before output because the current
planner treats the hidden initializer as a normal interface boundary but has no
conversion decision for an abstract `Map` source. The earlier nested local
`StringMap`-to-`IMap` case passes and must remain boxed.

## Decision

The `IMap` boundary plan owns a new plain-data local-initializer disposition:
`standard-map-storage-alias`. It is not a general representation for
`haxe.IMap`, and it is not a syntax shortcut.

The planner may seal that disposition only when all of these facts hold:

1. the local's declared type is the exact upstream `haxe.Constraints.IMap<K,V>`;
2. its initializer has the exact upstream `haxe.ds.Map<K,V>` abstract type;
3. the key kind selects one target-supported standard carrier—String, Int, or
   object identity—and the key/value types agree with the local;
4. every read of that local in the same final typed function is the first
   argument of an exact target-authored `haxe.ds.NativeHxMap` static operation;
5. each read is behind a typed cast to the matching standard carrier and the
   native operation's name agrees with that carrier kind;
6. there is at least one such use; and
7. there is no assignment, return, capture, interface call, generic call,
   comparison, storage in another value, or other local read.

The decision records the source span, key/value semantic types, key kind,
native carrier ID, approved operation/use inventory, proof identity, and exact
function/program/body/pipeline revisions. Its identity does not use the local's
generated name. Host local IDs may index the request-local scan but do not
become saved evidence.

`coerceLocalInitializer` asks the active `IMap` plan for this exact occurrence.
If present, it builds the initializer without a dispatch adapter. If absent, it
continues through the ordinary fail-closed `IMap` conversion path. No other
assignment, argument, or return path may consume the alias disposition.

## Why this owner

This is a choice between two meanings at an `IMap` boundary: build the public
interface carrier, or preserve storage for a closed target-stdlib expansion.
The existing `IMap` planner already owns that boundary and already has separate
root/nested function lifetimes. The general local-representation registry
should not claim that arbitrary `IMap<K,V>` locals use raw `HxMap` storage.

The raw local needs no special OCaml type annotation in the admitted case: its
non-null initializer is emitted directly and OCaml infers the concrete map
carrier. If a future case needs a mutable cell, null default, capture, or other
annotation, this proof rejects it and a separate representation design is
required.

## Rejected alternatives

- **Box every hidden local and unwrap later:** semantically possible, but it
  adds carrier layout and unwrapping behavior to every standard Map operation,
  including the compiler's map-heavy hot path. It is unnecessary for this
  closed expansion and would broaden runtime risk.
- **Treat every `Map`-to-`IMap` boundary as raw storage:** unsound. User-visible
  `IMap` calls require the checked dispatch record, and user implementations do
  not share `HxMap` storage.
- **Change `NativeHxMap` parameter types:** already tested and reverted. The
  `IMap` temporary is created before those target helper signatures decide the
  final call.
- **Recognize `this1`, source text, or source positions:** fragile and
  prohibited. Only exact typed declaration identities and a closed use graph
  are admissible.
- **Make handwritten OCaml infer or repair the value:** violates semantic
  ownership and cannot fail before output publication.

## Tests before the compiler-scale retry

1. Keep the existing nested concrete `StringMap`-to-`IMap` fixture and prove it
   still creates one nested interface conversion and one interface call.
2. Make the static `Map` field operation green and require one storage-alias
   decision for each hidden local, with no extra interface conversion.
3. Add an ordinary `Map` value explicitly assigned or passed to `IMap`; require
   a real standard adapter and successful interface dispatch.
4. Add negative planning fixtures where a candidate local is also returned,
   captured, assigned, compared, called through `IMap`, or passed to a non-map
   function; each must reject storage-alias admission.
5. Cover String, Int, and object-key standard carriers. Do not claim enum-key
   closure unless the target's distinct enum-map contract is implemented and
   tested.
6. Corrupt one saved alias carrier, operation, and pipeline revision and require
   the inspector to reject each report.
7. Run the focused control-plan contract before the multi-minute compiler
   workload so missing nested ownership or malformed decisions fail quickly.

## Stop conditions

Stop and redesign if the typed use graph cannot distinguish the target-authored
native operation by canonical declaration identity, if an admitted local needs
capture or mutation, if a normal `Map`-to-`IMap` conversion cannot remain
boxed, or if generated OCaml needs a cast/`Obj.magic` to make the alias compile.

## Review provenance

The focused caf-oracle request
`orq_20260809T001315Z_6feca43b` was prepared with verified hashes. Three safe
staging attempts, including one authenticated browser restart, failed before
upload because the provider model control was unavailable. The ledger remained
at `dispatchSafety: not_attempted`. This written second pass is the repository's
allowed xhigh fallback; it does not claim an external Oracle response.
