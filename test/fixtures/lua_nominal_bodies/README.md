# Lua class behavior

Run `haxe test/m14_lua_nominal_bodies_integration_test.hxml` from the repository root.
The check requires upstream Haxe and Lua. It compares both executions with `expected.stdout`.

Two child objects inherit a constructor that writes a field and prints once per object.
An override reads that field through a nested receiver call. An extracted method keeps its original receiver after the field changes.
The second object remains independent, and an inherited method returns the original object.

This fixture supports haxe_ocaml-2x217.1. It does not replace the import-alias integration test or prove the parent's null-safe contract.

The fixture also checks zero-based array reads and writes, field-initializer order around an explicit parent call, and authored names that could capture generated bindings.
The normal `test:m14:lua-typed-local-projection` command includes this regression.

A captured static helper calls another helper. Both bodies must survive exact declaration-based reachability.
The fixture also executes an array-stored closure with a captured receiver and an immediately invoked closure.
