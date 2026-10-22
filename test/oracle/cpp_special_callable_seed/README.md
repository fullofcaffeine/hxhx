# Specialized C++ callable parameters

This fixture sends an integer, an absent optional integer, and a boolean through
`Assert.q`. The argument named `T` must not collide with the generated template
parameter. The effectful integer expression must run once.

It also forwards an integer and an absent optional integer through `Serializer.run`.
The source argument named `s` must not collide with the generated serializer local.
This small serializer observes argument passing, not the standard serialization format.

The `Lambda.has` cases exercise string and integer arrays, literals, and empty arrays.
An untyped empty array gets its element type from the other argument.
The source parameter `x` must remain distinct from the generated loop variable.
The effectful element expression must run once.

The `Assert.sameAs` cases mutate a structural status record in the caller.
They cover matching and different integer values with zero approximation, and an omitted source default.
Generated C++ must pass that record by mutable reference and retain the Boolean result type.
These cases do not change or establish general floating-point comparison policy.

The `Assert.same` cases pass equal integers, different integers, and absent optional values.
They exercise omitted and supplied optional arguments and count a single argument evaluation.
The source parameter named `__hxhx_status` must remain distinct from generated status storage.

The `Test.eq` cases count assertion calls for equal, different, and absent values.
The native test runs both source declarations: one with an optional position, and one without a position parameter.
The second declaration requires a separate target-only trailing argument. Both variants must preserve the same source behavior.

The neutral `exc` and `unspec` wrappers receive effectful callback factories.
Each factory must run once, and neither authored empty wrapper executes its callback.
These cases verify callback passing through the unit-test support class route, not exception-assertion semantics.
An explicit callback invocation then verifies that discarding its result preserves its effect exactly once.
The native driver rejects unused-value warnings in the generated source.

The neutral `t` and `f` wrappers receive an effectful integer and an absent optional value.
Their signatures must preserve both carriers, source-generic name collisions, and one argument evaluation.
Their authored empty bodies isolate argument passing from assertion semantics.

The neutral `allow` wrapper shares one generic type between a value and its collection.
Calls cover strings, an empty array, an effectful integer, and optional elements.
Both source-position variants must compile and retain the same evaluation count.
A third variant uses source `Dynamic` parameters, so C++ owns the shared generic.
Its empty array must use deduction from the value argument without naming a private template in the caller.

Run the source behavior with upstream Haxe:

```sh
haxe -cp test/oracle/cpp_special_callable_seed/src -main Main --interp
haxe -D eq_without_pos -cp test/oracle/cpp_special_callable_seed/src -main Main --interp
haxe -D eq_without_pos -D allow_without_generic -cp test/oracle/cpp_special_callable_seed/src -main Main --interp
```

Run generation, native C++ compilation, and the stdout comparison:

```sh
haxe test/m14_cpp_special_callable_integration_test.hxml
```

The independent expectation is `expected.stdout`. The metadata-accessor signature
checks live in `M14CppSpecialCallableContractTest`; this runtime fixture tests `q`
and serializer forwarding, dependent iterable arguments, status mutation, and source or target-added assertion arguments.
