# Module functions and class methods

Ordinary module functions can call classes declared in the same Haxe module.
This fixture covers both source declaration orders and mutual calls between a
class method and a module function. Native execution must match eval.

Two static initializers append to an event list. Their observed order must remain
`first,second` when the target orders the callable declarations.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_function_class_value_order bash scripts/test-portable.sh
```

The fixture extends the reduced `Unbound value add` failure from native compiler
promotion. It does not establish full compiler or performance readiness.
