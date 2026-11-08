# Stage3 catch of runtime file-system failures

`Main.hx` makes file-system calls that fail, such as reading a missing file
or removing a missing directory, and prints what each `catch` handler
receives.

Before the fix, a native Stage3 program could not catch these failures. The
OCaml runtime reports them with OCaml exceptions such as `Sys_error`, but the
generated `catch` only matched exceptions raised by a Haxe `throw`. So this
program stopped at its first read:

```haxe
try sys.io.File.getContent("missing.txt") catch (e:Dynamic) trace("fallback");
// native: Fatal error: exception Sys_error("missing.txt: No such file or directory")
// upstream Haxe 4.3.7: prints the fallback
```

Upstream Haxe 4.3.7 (`--interp`) reports each failure as a `String`, so
`catch (e:Dynamic)`, `catch (e:String)`, and `catch (e:haxe.Exception)` all
handle it. The fixture checks those handlers, the exact message text for each
call, a handler for another type that must let the failure reach an outer
handler, `return`, `break`, and `continue` inside a `try` (including a
`return` from a closure and a `break` from a `haxe.Exception` handler), and
`haxe.Exception` handlers for thrown `Int`, `Float`, and `Bool` values, and
a user subclass of `haxe.Exception` caught as `haxe.Exception`, as its own
type, and by an outer handler after a non-matching inner one. It also uses
`try` as a value (`final x = try read() catch (e:Dynamic) "fallback";`).

The fixture also rethrows from `catch (e:haxe.Exception)`. The outer handler
must see the original value, not the exception object that wrapped it, for a
thrown `String`, `Int`, `Float`, `Bool`, or enum and for a runtime failure.

An exception the program builds with a third `native` constructor argument is
not such a wrapper. Throwing one keeps the exception object and its subclass,
whether it is thrown directly, from a local, a static field, a call result, or
a `Dynamic` value, or after being caught and rethrown.

A statement `try` whose body is not a block (`try f() catch (e:String) g();`)
still loses its handlers in the parser. That is owned by `haxe_ocaml-2aql5`.

The test also builds a native-only program that raises an OCaml `Failure`,
the runtime's report for its own bugs, inside `catch (e:Dynamic)`. That
handler must not run: the failure must stop the program.

`npm run test:m14:stage3-runtime-exception-catch` checks that upstream Haxe
prints `expected.stdout`. It then builds the program with Stage3 and requires
the native executable to print the same text.

`Std.string(e)` on a caught `haxe.Exception` object is not checked here; it
is owned by `haxe_ocaml-czx3v`.
