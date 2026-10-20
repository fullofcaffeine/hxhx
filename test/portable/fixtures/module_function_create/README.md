# Module-level factory

A Haxe module can declare a function named `create`. Calling `Factory.create(7)` must print `8` in both eval and native OCaml.

Previously, the compiler also emitted a synthetic class constructor named `create` for the module. The duplicate binding failed the native build. This fixture keeps warnings enabled and checks the authored function against upstream Haxe.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_function_create bash scripts/test-portable.sh
```
