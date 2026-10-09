# Managed C++ String concatenation

Run the focused contract from the repository root:

```sh
npm run test:m14:cpp-managed-string-concat
```

The test compares authored Haxe with an independent output file. It executes upstream Haxe and the generated native C++ program. Cases cover both operand orders, null Strings, effect order, Unicode, and embedded zero bytes. Integer addition and String equality must retain their existing behavior.

The native observer also checks null operands under address and undefined-behavior sanitizers, at two optimization levels.

The `dynamic/DynamicConcat.hx` contract stores primitive values as `Dynamic` before concatenation. It covers Boolean, Int, String, and null values. Assertions check both operand orders, Unicode, embedded zero bytes, once-only effects, evaluation order, and local String compound assignment. The test runs upstream eval and generated native C++, including forced collection with both sanitizer profiles. It also checks that compilation preserves the original typed modules.

The same source passes native Haxe 4.3.7 with hxcpp 4.3.2. With that toolchain available, reproduce it with:

```sh
haxe -cp test/oracle/managed_string_concat_seed/dynamic -main DynamicConcat -cpp .tmp/upstream-dynamic-concat
.tmp/upstream-dynamic-concat/DynamicConcat
```

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

Object concatenation remains unsupported, including objects stored as `Dynamic`. It needs the actual conversion rules, including user `toString` effects. Exact unsupported types fail during compilation. Unsupported runtime tags at a `Dynamic` boundary fail before returning concatenated text. Task `haxe_ocaml-w49go` remains open, with related formatting work in `haxe_ocaml-qd2p5` and `haxe_ocaml-hcnk8`.

Float conversion requires the repository's numeric review gate. This test does not establish Float formatting, object conversion, compound assignment through fields or array elements, or full C++ compatibility.
