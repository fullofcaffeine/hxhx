# Nullable function values

An optional parameter and a nullable instance field hold the same concrete
callback type. Calls preserve enum arguments, nullable enum results, and captured
state. Absent and cleared callbacks are not called. Replacing the field changes
the next call.

The callback is captured before argument side effects can replace its field.
Arguments run before a null invocation raises a catchable exception. Parameterized
closures preserve a nullable enum result without claiming a complete parameter
plan. Public inspection rejects forged callable ownership, changed enum identity,
missing result evidence, and the previous report schema.

The fixture compares native execution with independently specified output and
upstream Haxe/eval. Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=nullable_function_value bash scripts/test-portable.sh
```
