# Try/Catch and Exceptions (Portable Mode)

This backend implements Haxe `throw` / `try` / `catch` using **OCaml exceptions**,
while keeping Haxe’s “throw any value” behavior.

The design goal is:

- predictable `catch (e:T)` behavior for a useful set of types,
- correct control-flow behavior under `-warn-error` (no accidental swallowing of
  internal control exceptions), and
- the ability for `catch (e:Dynamic)` to catch both Haxe-thrown values and
  “real” OCaml exceptions raised by OCaml stdlib calls.

## The Runtime Wrapper: `HxRuntime.Hx_exception`

In OCaml, exceptions are values of type `exn`, and you normally only raise values
of exception constructors.

Haxe is different: you can `throw` **any** value (including primitives like `0`
or `true`, strings, class instances, etc.).

To bridge this gap, the backend wraps thrown values in a dedicated runtime
exception:

- `HxRuntime.Hx_exception of Obj.t * string list`

Where:

- `Obj.t` is the boxed payload (`Obj.repr <value>` in codegen).
- `string list` is a list of **type tags** used to implement typed catches.

## `throw` Lowering

In portable mode, `throw e` lowers to:

- box the value: `Obj.repr <e>`
- compute *best-effort* tags from the **static type** of `e`
- raise `HxRuntime.Hx_exception` via `HxRuntime.hx_throw_typed`

### Tags

Tags exist because OCaml’s runtime representation cannot reliably distinguish
some Haxe values with `Obj` inspection alone.

Example:

- In OCaml, `int` and `bool` are both “immediate” values at runtime, so you
  cannot safely tell them apart in a generic `catch`.

The backend therefore emits tags like:

- `Int`, `Bool`, `Float`, `String`
- fully-qualified Haxe class/interface names (`pack.TypeName`)
- for class throws: it also includes superclasses and implemented interfaces

The list always includes `Dynamic`, so a catch-all is predictable.

## `try/catch` Lowering

`try { ... } catch (...) { ... }` lowers to an OCaml `try ... with`:

- `Hx_break`, `Hx_continue`, and `Hx_return` are **re-thrown** immediately (these
  are internal control-flow exceptions used by other lowering passes).
- `Hx_exception (value, tags)` is handled by running the Haxe catch chain:
  - `catch (e:Dynamic)` matches unconditionally.
  - `catch (e:T)` matches by checking `HxRuntime.tags_has tags <tag-for-T>`.
  - first match wins; if nothing matches, the exception is re-thrown.
- Any other OCaml exception (`exn`) can be caught by `catch (e:Dynamic)`.
  - If no catch matches, the original OCaml exception is re-raised.

## Current Limitations (Important)

### Static-type tagging (no full RTTI yet)

Tags are computed from the **static type** of the thrown expression.

That means this will *not* behave like full runtime type tests in all cases:

```haxe
var e:Base = new Child();
try {
  throw e; // static type is Base
} catch (c:Child) {
  // Not guaranteed to run at this milestone.
}
```

Because the tags are derived from `Base`, the backend does not currently “peek”
into the runtime shape to discover `Child`. Supporting this would require a
proper runtime type identity strategy (RTTI), which is intentionally deferred.

### Typed catches for “non-Haxe” exceptions

OCaml exceptions raised by OCaml stdlib code are not tagged as Haxe types.

- `catch (e:Dynamic)` can catch them.
- Typed catches (`catch (e:T)`) are not expected to match them.

