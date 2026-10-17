# C++ local binding contract

The fixture keeps three same-named functions distinct after closures capture them.
It also checks collisions with an existing suffix and a C++ keyword.
The first six output lines identify each selected function and local value.
The final three lines test an integer parameter beside a string local and a boolean local.
Their names collide after C++ keyword escaping, including an explicitly authored suffix.
Arithmetic, string conversion, and branching must each use the correct binding and type.
The loop check also keeps an integer loop variable separate from a captured string.
It throws on a mismatch and leaves the nine-line expected output unchanged.
The comprehension captures a user variable named `__hxhx_comp_out`.
Compiler-created result storage must use a different symbol and preserve that value.
A bound method also captures `second` while its remaining parameter has that name.
The generated wrapper must pass the captured value and the supplied argument separately.
Another bound method keeps `int` and `int_` parameter slots distinct.
A materialized range also captures a user variable named `__hxhx_range_out`.
Its generated result vector must not replace that integer endpoint.
The specialized `isOfType` helper also keeps `int` and `int_` parameters distinct.
Its authored body must use the same binding plan as its generated signature.
Calls also pass an absent integer, callback, and object to its `Dynamic` parameters.
Argument conversion must preserve each absent value until the function tests it.
The fixture computes all three results before it checks them individually.
Unwrapping the absent integer before the call causes the native program to abort.

Run the Haxe 4.3.7 baseline:

```sh
haxe -cp test/oracle/cpp_strict_local_binding_seed/src --run Main
```

Run the native C++ check:

```sh
haxe test/m14_cpp_strict_local_binding_integration_test.hxml
```

The check requires a C++ compiler and compares runtime output with `expected.stdout`.
The generated-source C++ smoke runs it too.
The test also checks exact source keys in call and map inference, optional storage,
and direct callback rendering before it runs the native observer.
