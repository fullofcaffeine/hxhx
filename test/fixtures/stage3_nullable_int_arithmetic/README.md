# Stage3 arithmetic on Null<Int> values

`Main.hx` uses `Null<Int>` values directly in Int arithmetic, ordered
comparisons, and loop conditions. The values come from `String.charCodeAt`
(which returns `Null<Int>`), `Map.get`, an `Array<Null<Int>>` read, a
`Null<Int>` instance field, and an optional `?step:Int` argument. They appear
in locals, fields, `if` conditions, a `while` condition, a `for` loop, and a
digit-parsing loop (`value * 10 + (s.charCodeAt(i) - 48)`).

Before the fix, sums such as `s.charCodeAt(0) + s.charCodeAt(1)` printed `0`
in the native program. The emitter recognized a nullable operand only when it
was a local variable. A nullable call result matched no Int case, and when
neither side of an operator was recognized, the emitter wrote the placeholder
`(Obj.magic 0)` in place of the whole expression. When only one side was
recognized, the nullable value was read without a null check, so
`"abc".charCodeAt(10) - 48` printed a garbage number instead of failing.

Now any operand whose recorded type is `Null<Int>` or `Null<Float>` is
unwrapped through the checked runtime helper after both operands ran. A null
operand raises a catchable error. Upstream `--interp` also raises a catchable
error (`Invalid operation: null - 48`); the native message is `Null Access`,
so the fixture prints only that an error was raised.

`npm run test:m14:stage3-string-methods` checks that upstream Haxe 4.3.7
prints `expected.stdout`. It then builds the program with Stage3 and requires
the native executable to print the same text.
