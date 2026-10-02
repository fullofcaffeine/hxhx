# Core Array and String class objects

This fixture checks class values, `is` predicates, null rejection, and reflection
identity for the native Array and String representations. Authored Haxe runs
with upstream Haxe 4.3.7/Neko and both generated Neko layouts.

Run `haxe test/m14_neko_runtime_type_registry_integration_test.hxml`.

The shared typed target distinguishes core types from nominal declarations.
Array class values erase the element type as `Class<Array<Dynamic>>`. String
class values have `Class<String>`. Both use the same registry objects as
`Type.getClass`.

Numeric targets, exact `Std.isOfType` calls, typed catches, and other native
carriers remain unfinished work under `haxe_ocaml-41m6r`.
