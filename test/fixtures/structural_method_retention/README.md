# Class methods exposed through record types

Returning a class as a record type must preserve the methods that the record
exposes. The caller can invoke those methods without knowing the class name.
Previously, full unused-code removal kept the constructor but removed the methods.

Run `haxe test/m14_structural_method_retention_test.hxml` from the repository root.
The test runs the authored program with upstream Haxe 4.3.7 and the local compiler.
Both must finish without output or an exception.

The fixture covers return values, local variables, call arguments, and an inherited
generic method. A feature assertion proves that an unused exposed method remains
reachable. Another assertion proves that construction alone does not retain
same-named methods on an unrelated class.

The test requires a resolved record return type before dependency discovery.
Inline method-shaped annotations have a separate resolution defect, tracked as
`haxe_ocaml-idcbb`. Named typedefs isolate this retention regression.

This fixture does not prove every structural conversion boundary or general
JavaScript compatibility. Constructor arguments, optional defaults, property
accessors, explicit unsafe casts, and nested aggregate conversions need separate
evidence before broader claims.
