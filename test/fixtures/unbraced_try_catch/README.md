# Unbraced try and catch

`Main.hx` writes `try` bodies and `catch` handlers without braces in every
position Haxe allows, and prints which handler ran:

```haxe
try fail("one") catch (e:String) note("caught " + e);
for (index in 0...2)
	try fail("for " + index) catch (e:String) note(e);
final value = try fail("value") catch (e:String) e.length;
```

Upstream Haxe 4.3.7 runs each handler. Before the fix, the hxhx statement
parser read an unbraced try body with the caller's stop rule. Its statement
recovery then skipped every token up to the next `;`, including the whole
`catch (e:String) ...` clause. The try kept no handlers at all, so the thrown
value escaped (`Fatal error: exception HxRuntime.Hx_exception("one", _)` on
the native route, an uncaught error on JavaScript). An unbraced handler after
an unbraced body could also leak out as an ordinary statement.

The fixture covers one and several catches, if/else branches, `for` and
`while` bodies, `try` as a value and as an argument, nested tries (every
following `catch` belongs to the innermost `try`, as upstream parses it),
a rethrow, and unbraced handlers after braced bodies.

`npm run test:m14:unbraced-try-catch` checks that upstream Haxe prints
`expected.stdout`, then runs the same program through the hxhx JavaScript
route and the Stage3 native route. It also checks the parsed shape directly,
and that `try f(); catch (e:String) g();` is rejected, as upstream rejects it.

`log` is cleared in place, because Stage3 does not store writes to static
fields yet (`haxe_ocaml-ailt8`).
