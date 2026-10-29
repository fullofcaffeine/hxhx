# Source do/while and return destinations

This program checks a do/while loop inside a value block.
The body runs before the first condition check.
`continue` reaches the trailing condition, while `break` skips that condition.
Returns still exit the original method or nested function.
A return inside a plain value block also exits its method and determines its inferred result type.

The expected output comes from upstream Haxe 4.3.7.
The native test requires the same output and checks that lowering leaves the original typed functions unchanged.
It also checks that repeated lowering preserves the same revision.

From the repository root, run:

```sh
haxe -cp test/oracle/source_do_while_seed/src --run Main
haxe test/m14_source_do_while_syntax_test.hxml
haxe test/m14_source_do_while_test.hxml
```

The syntax test checks macro loop kind, source reconstruction, revision changes, and malformed loop rejection.
Condition expressions that require separate statement execution remain unsupported by shared lowering.
Full source-control and upstream-suite acceptance remain tracked under `haxe_ocaml-o25kr`.
