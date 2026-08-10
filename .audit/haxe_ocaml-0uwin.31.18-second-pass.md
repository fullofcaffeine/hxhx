# Second-pass review: standard Array map and filter

## Outcome

The sealed call model is sound for this slice. It derives callback and result
types from Haxe's typed function data. The OCaml printer only consumes that
decision. It no longer decides `map` or `filter` from a method name.

The review found two proof gaps and fixed both before closure:

- The inspection test allowed zero `map` or `filter` rows. A real portable
  fixture now executes both operations, and the test requires both rows.
- A missing nullable report field was treated like an explicit JSON `null`.
  The reader now requires the field to exist and rejects its removal.

## Challenged invariants

- `map` seals `(T) -> U` and checks that the call result is `Array<U>`.
- `filter` seals `(T) -> Bool` and preserves `Array<T>`.
- Callback parameter names do not participate in semantic identity.
- Nullable callback types keep their nullability during identity checks.
- The receiver and callback expression each run once, in source order.
- Empty arrays do not invoke callbacks.
- Mapping and filtering do not mutate the source array.
- Integer, float, String, nullable, and object storage have executable or
  focused coverage appropriate to this slice.
- Each generated private runtime call has a sealed owner and requirement.
- The private-reference inventory decreases only for `HxArray.map` and
  `HxArray.filter`, from 334 to 332 entries.

## Scope decision

An `Int -> String` executable tracer exposed a separate, pre-existing
String-default requirement mismatch. The final reconciliation correctly
rejected an unused planned requirement. This slice does not weaken that check.
It uses an `Int -> Float` executable type change and retains the exact String
result proof in the call-plan fixture. A separate child tracks the runtime
requirement correction.

No Oracle review was needed. The implementation boundary was bounded, the
installed Haxe 4.3.7 behavior oracle was clear, and focused plus vertical tests
converged. README goals and runtime source-selection readiness do not change.
