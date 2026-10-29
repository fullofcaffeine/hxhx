This fixture checks imported class owners in generated C#.
Two packages expose classes named `Provider` with distinct empty static methods.
Aliases select those owners without ambiguous namespace imports.
A secondary class, a root-package class, and a same-package class cover declaration-to-target name mapping.

Calls to the empty methods check static owner selection during native compilation.
The primary, root-package, and same-package constructors must return instances before the entrypoint prints their expected lines.
The secondary class is tested through its static call and an assertion on the emitted receiver.
The test compares the independent expectation with upstream Haxe and native C# in both root-package modes.
It also checks the emitted aliases for the selected owners.
This test does not prove helper method body emission.
Nonempty helper bodies and secondary construction remain tracked by `haxe_ocaml-2x217`.
A factory returning an instance currently produces null, and secondary construction can select a nested import stub.

Run `haxe test/m14_cs_source_type_imports_integration_test.hxml`.
When Mono and a C# compiler are unavailable, the test reports source-only coverage explicitly.
