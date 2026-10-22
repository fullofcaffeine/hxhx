# JavaScript runtime type operands

Run `haxe test/m14_js_runtime_type_operands_test.hxml` from the repository root.
Upstream Haxe and generated JavaScript must match `expected.stdout`.
The program tests parent classes, transitive interfaces, unrelated types, null,
class values, field initializers, and an operand that prints before its type test.
The harness compares both upstream evaluation and upstream JavaScript on Node.
It also rejects copied, mutated, or foreign runtime type operands. Unsupported
`Int`, `Float`, and `Bool` type objects must leave an existing output file intact.
Task `haxe_ocaml-srnqf` owns the remaining runtime type support.

The test remains a prerequisite of `test:m14:js-target-core-js-lib-runtime`.
The library test loads real providers and must execute its compiled Neko runner.
Its standard-library path also needs runtime type operands for `Int64.isInt64`.
Core type objects, same-name declarations, and `Std.isOfType` still need coverage
and implementation before that task can close. This fixture does not prove general
runtime type compatibility or change README Goals.
