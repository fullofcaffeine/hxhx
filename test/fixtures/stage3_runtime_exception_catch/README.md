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
handler, and `return` and `break` inside a `try`.

`npm run test:m14:stage3-runtime-exception-catch` checks that upstream Haxe
prints `expected.stdout`. It then builds the program with Stage3 and requires
the native executable to print the same text.

`Std.string(e)` on a caught `haxe.Exception` object is not checked here; it
is owned by `haxe_ocaml-czx3v`.
