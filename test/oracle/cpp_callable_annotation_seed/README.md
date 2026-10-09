# Mutable callback results

This fixture assigns callbacks with String, Int, Bool, and null results to one `String->Dynamic` local.
Arithmetic, Boolean branching, null comparison, and counters detect string conversion or repeated evaluation.
The separate inferred local keeps its String result.
Shadowed callback locals also prove that `bind` keeps the selected declaration, preserves defaults, and injects optional `haxe.PosInfos` values.
The native test loads the installed `haxe.PosInfos` declaration into the same typing index as the fixture.
Loop and catch callbacks execute through the internal control-body projection and keep their String results.
Both branches of an annotated callback return through a local binding; a counter checks that each call runs once.
A Void callback invokes a nested Int callback, proving that each function keeps its own result contract.

Run the upstream expectation with `haxe -cp test/oracle/cpp_callable_annotation_seed/src --run Main`.
Run the native observer with `haxe test/m14_cpp_callable_annotation_integration_test.hxml`.

This fixture covers callable result storage. It does not establish full Dynamic or target parity.
