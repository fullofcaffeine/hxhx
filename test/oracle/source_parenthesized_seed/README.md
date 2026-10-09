# Parenthesized source expressions

This fixture checks grouping as source syntax, through macro conversion and native execution.
Upstream Haxe 4.3.7 supplies the independent syntax and behavior expectations.

Run the upstream probes:

```sh
haxe -cp test/oracle/source_parenthesized_seed/src -main ProbeMain --interp
haxe -cp test/oracle/source_parenthesized_seed/src -main Main --interp
```

Compare the results with `syntax.stdout` and `expected.stdout`.
Nested grouping must survive macro conversion as nested `EParenthesis` nodes.
The native program checks precedence, assignment results, and calls through grouped function values.
Its function named `__hxhx_parenthesized` is an ordinary user declaration.

Grouping an entire assignment is valid. Grouping its destination is invalid:
`(value = 3)` succeeds, but `(value) = 3` must fail with `Invalid assign`.
The rejected fixture preserves the latter case. The syntax test also rejects grouped compound assignments and increment destinations.

Run the compiler checks:

```sh
haxe test/m14_source_parenthesized_syntax_test.hxml
haxe test/m14_source_parenthesized_native_test.hxml
haxe test/m14_source_parenthesized_macro_test.hxml
haxe test/m14_source_local_assignment_control_test.hxml
```

The macro adapter check now preserves the assignment inside the group.
Binary operators use a shared typed mapping, including nested `OpAssignOp` values for compound assignments.
Comparisons such as `>=` remain comparison operators.

The extended probes compare 36 operators and 20 precedence cases with upstream:

```sh
haxe -cp test/oracle/source_parenthesized_seed/src -main BinaryMain --interp
haxe -cp test/oracle/source_parenthesized_seed/src -main BinaryPrecedenceMain --interp
haxe test/m14_macro_binary_operator_test.hxml
haxe test/m14_macro_binary_native_test.hxml
```

The native test requires C++, Node.js, Python, PHP, Neko, and GNU `timeout` (`gtimeout` on macOS).
It emits macro values from authored expressions into the observer templates, then compiles or runs each target.
Each observer checks two grouping nodes, the binary operator and its arguments, and the order of the left and right operands.
Output must match `binary.stdout`, which comes from the upstream macro probe.

These checks do not establish complete macro enum metadata, source-position accuracy, or project-macro argument transport.
Track the remaining work in `haxe_ocaml-xq2ke` and the expression-macro owner `haxe_ocaml-9sj5p`.
