# Stage3 nullable call arguments

Haxe lets you pass a `Null<Int>` where an `Int` is expected:

```haxe
String.fromCharCode(Std.parseInt("65")); // "A"
```

On the native route, a `Null<Int>` (and `Null<Float>`, `Null<Bool>`) lives in a
boxed carrier (`Obj.t`), but a concrete `Int` parameter takes a native OCaml
`int`. Ordinary Haxe calls already converted the value at that boundary.
Before the fix, the native call adapters did not: `String.fromCharCode`,
`Array` methods (`push`, `insert`, `slice`, ...), `Map` keys, and `Math.abs`
received the carrier as-is, and ocamlopt rejected the program with "This
expression has type Obj.t but an expression was expected of type int".

`Main.hx` passes non-null nullable values to each of those calls, and to
ordinary static, instance, and constructor calls as a regression check.
`npm run test:m14:stage3-nullable-call-arguments` checks that upstream Haxe
4.3.7 prints `expected.stdout`, then requires the Stage3 native executable to
print the same text.

## Null values

`../stage3_nullable_call_arguments_null` is native-only. A native `int` cannot
hold null, so the conversion throws the catchable Haxe String `Null Access`
(the existing `HxRuntime.nullable_int_unwrap` rule that ordinary calls
already use). Upstream differs by target:

- `--interp` (eval) also throws `Null Access` for `String.fromCharCode(null)`.
  But it passes null into a Haxe function's `Int` parameter, and it stores null
  in an `Array<Int>`.
- Static targets such as C++ and HashLink read 0.

## Not covered here

- Calling a function value (`final f:Int->Int = ...; f(nullable)`) still fails
  emission. That needs a new conversion in the shared callable lowering
  (Bead `haxe_ocaml-sk7hr`).
- Whole-number Float text (`3` printed as `3.`) is Bead `haxe_ocaml-iffj5`, so
  the `Math.abs` result is printed through `Std.int`.
