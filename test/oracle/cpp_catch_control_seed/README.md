# Native carrier catch control

These functions catch values through `Dynamic` and standard `Any`. A handler
must preserve payload identity and the surrounding function or loop destination.
Returned closures must retain separate mutable catch variables after unwinding.

Run the independently authored upstream expectations with Haxe 4.3.7/hxcpp:

```sh
haxe -cp test/oracle/cpp_catch_control_seed -main ReferenceMain -cpp .tmp/cpp-catch-control-reference
.tmp/cpp-catch-control-reference/ReferenceMain
```

Success means exit status zero and empty stdout/stderr. Apply the repository's
background scheduling policy to native builds.

Run `haxe test/m14_cpp_catch_control_test.hxml` for the candidate. It generates
the complete authored function and closure bodies through production emitters.
The independent native observer checks payload identity, null, nested rethrows,
expression results, handler returns, loop break/continue, and escaping closures.
It forces collection and requires complete cleanup at O0/O2 with ASan/UBSan.
It does not supply handler selection, catch entry, or handler bodies itself.
Ownership negatives reject copied statements, foreign projections, changed
bodies, and missing typed catch-use facts.

Carrier handlers accept every value in the native thrown-value transport.
Other handler views still require runtime classification and real exception
providers. This fixture does not prove typed numeric matching, wrapping, or
conversion of native runtime errors. The full exception suite remains required
under `haxe_ocaml-qrk0u` and includes complete field-initializer execution.
