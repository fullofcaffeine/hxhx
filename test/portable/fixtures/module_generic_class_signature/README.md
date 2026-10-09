# Generic callbacks with class values

The same Haxe program must preserve object identity when a generic method calls a concrete callback.
The callback result crosses the method's general-purpose native storage, then returns to its exact class type.

This fixture checks class arguments and results, nullable objects, alias mutations, one callback invocation, and state restoration after failure.
Objects retain arrays, anonymous records, and cyclic references across calls.
Two separate classes retain their own type identities.
Two empty instances also remain distinct objects.
Whole-object transport does not authorize optimized field access.
The report checks require registered class representations and reject foreign or stale proof reuse.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=module_generic_class_signature bash scripts/test-portable.sh
```

This focused fixture does not establish native frontend readiness.
The full native parser, typer, and shared-target check remains separate acceptance evidence.
