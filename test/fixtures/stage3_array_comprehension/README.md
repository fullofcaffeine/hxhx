# Native array comprehensions

This fixture checks that native OCaml executes array comprehensions in the same
order as upstream Haxe. The expected output covers guarded yields, a nested
range and array loop, loop exits, an early function return, and array values.

The input, guard, and yield functions print their effects directly. This keeps
the order observer independent of mutable static storage. Boolean elements are
read directly, including values boxed by an ordinary Dynamic return. Array
joining and source type annotations have separate representation contracts.

Run the existing loop regression and this native observer with:

```sh
npm run test:m14:hih-forin
```

The focused command is:

```sh
haxe test/m14_ocaml_comprehension_test.hxml
```

The runner compares upstream and native output against `expected.stdout`.
It also rejects copied operations, operations from another projection, and
replaced operands. Emission must preserve the authored typed tree.

This contract covers comprehensions in ordinary methods. It does not claim
complete standard-library compilation or all field-initializer and closure
control forms.
