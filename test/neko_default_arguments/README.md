# Neko default arguments

Calling a function with an omitted argument must use its declared default.
For example, `value()` and `value(null)` both return `7` when the declaration
is `value(number:Int = 7)`. An explicit zero remains zero.

This fixture checks static methods, instance methods, constructors, extracted
functions, optional nullable arguments, false/zero values, and argument order.
Two parameter names occupy the usual generated argument-array names. The
compiler must choose a different name so binding one parameter cannot destroy
the remaining arguments.

Run the upstream Haxe 4.3.7 comparison and both generated Neko layouts:

```sh
haxe test/m14_neko_default_arguments_integration_test.hxml
```

The test compiles each generated Neko source and compares its runtime output
with `expected.stdout`. It also checks that required single-file parameters
retain fixed arity. The existing `test:m14:neko-typed-local-projection` group
includes this test. This focused contract does not establish full Neko parity.

Tracked by `haxe_ocaml-uhq12`.
