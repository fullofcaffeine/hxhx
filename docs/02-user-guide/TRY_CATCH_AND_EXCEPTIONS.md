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
- merge in *runtime* class tags for class instances (RTTI-assisted)
- raise `HxRuntime.Hx_exception` via `HxType.hx_throw_typed_rtti`

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
  - `catch (e:haxe.Exception)` matches unconditionally and binds `e` as:
    - the thrown value itself, if it already extends `haxe.Exception`, or
    - a `haxe.ValueException` wrapper, otherwise.
  - `catch (e:haxe.ValueException)` matches thrown values which do **not** extend
    `haxe.Exception`, plus explicitly thrown `ValueException` instances.
  - `catch (e:T)` matches by checking `HxRuntime.tags_has tags <tag-for-T>`.
  - first match wins; if nothing matches, the exception is re-thrown.
- Any other OCaml exception (`exn`) can be caught by `catch (e:Dynamic)`.
  - If no catch matches, the original OCaml exception is re-raised.

## Current Limitations (Important)

### Runtime tags are currently class-only

For class instances, the backend merges in runtime tag sets derived from each
instance’s `__hx_type` marker (see `Type.getClass`) and a generated registry.

This fixes the common case where the throw site is typed as a base class or
`Dynamic`, but the runtime value is a subclass.

Remaining gaps:

- **Enum values:** runtime tagging for enum instances is not implemented yet.
- **Dynamic primitive ambiguity:** in OCaml, `int` and `bool` are both immediates,
  so runtime inference is not reliable; typed catches rely on tags emitted at the
  throw site (follow-up work may add safer runtime strategies where possible).

### Typed catches for “non-Haxe” exceptions

OCaml exceptions raised by OCaml stdlib code are not tagged as Haxe types.

- `catch (e:Dynamic)` can catch them.
- Typed catches (`catch (e:T)`) are not expected to match them.

Exception: native Int `%` by zero (and `haxe.Int32` `%` by zero) does not raise
OCaml's `Division_by_zero`. The runtime throws the tagged Haxe String
`"Division by zero"`, so `catch (e:String)` matches it. See
`NUMERIC_SEMANTICS.md`.

## Runtime failures in hxhx native (Stage3) output

The hxhx native route (Stage3) uses the same `HxRuntime` module, but it
treats failures from the OCaml runtime as Haxe `String` values, as upstream
Haxe 4.3.7 does. For example:

```haxe
try {
  sys.io.File.getContent("missing.txt");
} catch (e:String) {
  trace(e); // Could not read file missing.txt
}
```

What happens at each Stage3 `try`:

- Every OCaml exception that reaches the `try` goes through
  `HxRuntime.catchable_exception`, the one place that decides what Haxe code
  can catch.
- A Haxe `throw` keeps its value and type tags.
- `Sys_error` becomes its message text. The file-system runtime
  (`HxFile`, `HxFileSystem`, `HxSys.setCwd`) shapes that text to match
  upstream, for example `No such file or directory(rmdir, missing)`.
- `Failure`, `Invalid_argument`, `Not_found`, `End_of_file`, and
  `Division_by_zero` become their printed OCaml form, for example
  `Failure("get_full_path")`.
- Each such value matches `catch (e:Dynamic)`, `catch (e:String)`, and
  `catch (e:haxe.Exception)`. A `haxe.Exception` handler receives an
  exception object whose `message` is the text.
- Everything else passes through unchanged: loop `break`/`continue`, each
  function's private early-return signal, and fatal conditions such as
  `Stack_overflow`.

Known gaps: the `haxe.Exception` object is a plain `haxe.Exception`, not a
`haxe.ValueException` (`haxe_ocaml-du1j7`), and `Std.string(e)` on it does not
call `toString` yet (`haxe_ocaml-czx3v`). The behavior is checked by
`npm run test:m14:stage3-runtime-exception-catch`.
