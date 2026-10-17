# Callback types in recursive modules

Pass and return ordinary Haxe callbacks through mutually dependent modules.
The exported OCaml signature keeps each argument and result type. A callback
with no arguments uses the target's existing unit argument.

The fixture checks captured state, exactly-once calls, returned closures, distinct
argument types in order, optional String arguments and propagated exceptions.
Unknown argument or result representations remain outside the export contract.
The macro also rejects optional scalar callbacks: their optional flag alone
does not establish a matching nullable native argument type.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=module_callback_signature bash scripts/test-portable.sh
```

Native execution and upstream Haxe/eval must match the independent expected output.
