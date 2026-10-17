# Enum parameters in recursive modules

Pass an ordinary enum through mutually dependent Haxe modules and run the same
source under eval and native OCaml. Previously, native module assembly rejected
the parameter because no optimized enum-returning method had registered its type.

The enum declaration already generates a named OCaml variant. The exported
function now retains that type without enabling a new call optimization.
The fixture checks String and Array payloads, exact retained signatures, and
the absence of an optimized result proof. Nullable arguments and results preserve
their boxed null-or-variant storage. Mutation through an Array payload proves
that a returned value keeps its original payload. Omitted and explicit-null
arguments behave alike. Generic and extern enums still fail the focused
signature projector's negative checks, including their nullable forms.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=module_enum_signature bash scripts/test-portable.sh
```

The runner builds and executes native output, then compares Haxe/eval with the
independent expected output. Other missing frontend declaration families remain
separate work.
