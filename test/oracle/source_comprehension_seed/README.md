# Authored comprehension contract

These fixtures describe syntax that macros must receive before execution is lowered.
They cover ordinary and guarded comprehensions, written parentheses, key/value bindings,
nested loops, and strings or comments that contain an arrow token.

Run the public syntax observer with pinned upstream Haxe 4.3.7:

```sh
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/src --run Main
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/src --run RuntimeMain
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/src --run ForMain
```

`ComprehensionContract.expected()` contains explicit constructor-shape expectations.
The upstream macro compares those expectations with `Context.parse` output.
`RuntimeMain` separately checks ordinary array and map behavior.
Syntax observations alone do not establish runtime equivalence.

Run the corresponding hxhx contract:

```sh
./node_modules/.bin/haxe test/m14_source_comprehension_syntax_test.hxml
```

This is a retained failing regression for `haxe_ocaml-20jan`.
It is not yet part of the passing CI command set.
The parser and shared typing must preserve authored structure before this task can close.
Do not replace the grouped inputs, discard guards, or accept synthetic helper calls as source syntax.
The task also requires binding, source-position, target-runtime, and combined regression evidence.
