# Functions in field initializers

This program creates functions in static and instance field initializers.
The static initializer declares a local counter and a named function that uses it.
The function retains its own loop, break, continue, and return destinations.
The instance initializer creates a function that returns its argument plus one.

Upstream Haxe 4.3.7 prints `4`, `4`, and `7` on separate lines:

```sh
haxe -cp test/oracle/source_field_initializer_control_seed/src -main Main --interp
```

Run the candidate typing and control-identity regression with:

```sh
haxe test/m14_source_field_initializer_control_test.hxml
```

That check also rejects return, break, and continue outside a nested function or loop.
It verifies exact replay identities and invalidation after an initializer edit.
The combined source-function control check includes this regression.
Typing evidence alone does not prove native closure lifetime or complete field-initializer emission.

The full native regression is:

```sh
haxe test/m14_source_field_initializer_native_test.hxml
```

It currently fails because field expressions reach backend projection before source control lowering.
The test retains both initializer functions and the escaping captured counter.
