# Boolean callback boundaries

Passing a `Dynamic -> Dynamic` callback to a `Bool -> Bool` parameter requires
Boolean argument and result conversions. Returning that method through a
`Bool -> Bool` result requires the same conversions at the return boundary.
Each converted value must preserve the original method identity.

This fixture covers a local callback argument, a callback argument supplied by
another call, and a converted method return. The callback checks the actual
Dynamic argument with `Std.isOfType`. A native integer representation cannot
silently stand in for a Boolean. Both `true` and `false` must survive every
round trip, and every result must compare equal to the original method.

Run upstream Haxe as the independent behavior reference:

```sh
node_modules/.bin/haxe -cp test/fixtures/ocaml_callback_bool_boundaries --run Main
```

The expected output is specified in `expected.stdout`. Native acceptance must
compile the same source, build it with Dune, and compare actual execution.
Report acceptance must also check nonempty Boolean helper inventories for
arguments and returns, including rejection of missing or foreign helpers.
The combined regression in `test/m14_dynamic_callable_conversion_test.hxml`
runs both native execution and `CheckOcamlCallableBoolReports` on this source.
This fixture belongs to `haxe_ocaml-v0zbr`; it does not establish overall
compiler or shared-target readiness.
