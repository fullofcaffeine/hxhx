# Real exception construction

This fixture constructs two real standard-library exceptions. It observes the
message, string conversion, previous-exception identity, and native identity.
The expected output is in expected.stdout.

```sh
haxe -cp test/oracle/cpp_exception_construction_seed -main Main --interp
haxe test/m14_cpp_exception_construction_test.hxml
```

Upstream Haxe 4.3.7 interpreter and native C++ output match the expectation.
The candidate currently rejects the common extern haxe.Exception provider.
The native test remains a required failing acceptance case until a production
provider and its runtime dependencies exist.

Do not replace the real dependency with a test class. This reduction does not
cover stacks, subclass dispatch, ValueException wrapping, or typed catch order.
