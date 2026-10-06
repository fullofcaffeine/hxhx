# Managed C++ String concatenation

Run the focused contract from the repository root:

```sh
npm run test:m14:cpp-managed-string-concat
```

The test compares authored Haxe with an independent output file. It executes upstream Haxe and the generated native C++ program. Cases cover both operand orders, null Strings, effect order, Unicode, and embedded zero bytes. Integer addition and String equality must retain their existing behavior.

The native observer also checks null operands under address and undefined-behavior sanitizers, at two optimization levels.

## A target-specific null case

Two null Strings behave differently across upstream targets. Haxe 4.3.7 with hxcpp 4.3.2 prints `nullnull`. The interpreter and Neko 2.4.1 throw instead. C++ concatenation must follow the observed C++ result.

The exact upstream input is in `upstream_null/Main.hx`. With hxcpp 4.3.2 available in your selected Haxelib environment, reproduce it with:

```sh
haxe -cp test/oracle/managed_string_concat_seed/upstream_null -main Main -cpp .tmp/upstream-string-null
.tmp/upstream-string-null/Main
haxe -cp test/oracle/managed_string_concat_seed/upstream_null -main Main --interp
```

The native callable observer uses `nulls/NullConcat.hx` to test both single-null orders and two nulls. Its expected C++ behavior comes from this upstream observation, not the interpreter.

## Remaining work

Object and Dynamic conversion remain unsupported in the managed implementation. They need their actual conversion rules, including user `toString` effects. The compiler rejects these categories explicitly. Task `haxe_ocaml-w49go` remains open, with related formatting work in `haxe_ocaml-qd2p5`.

Float conversion requires the repository's numeric review gate. This test does not establish Float formatting, String compound assignment, or full C++ compatibility.
