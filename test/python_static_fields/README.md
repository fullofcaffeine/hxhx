This fixture checks Python static fields in a class separate from `Main`.
Bare and qualified updates must share storage. Same-named locals, parameters,
and nested-block variables must remain separate. Instance fields remain on
their receiver.

Run `npm run test:m14:python-static-fields` to generate and execute Python.
The runner compares the output with `expected.stdout` and retains the artifact
under `.tmp/m14_python_static_fields` for review.

The expectation is independently specified. Compare upstream Haxe 4.3.7 with:

```sh
haxe -cp test/python_static_fields -main Main --interp
```

This fixture does not establish native compiler-host or upstream-suite parity.
