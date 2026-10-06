# Structural function signatures

Two modules call each other through functions that accept and return Haxe records.
Native output must preserve copied values, optional fields, and mutation through aliases.
The input also has an extra field, which must survive a narrower function parameter.
A record and a concrete class also cross the same function signature. The class
stores an array and calls back into the group from its constructor. This checks
the constructor signature and the array type in the recursive module interface.
Whole-program inheritance facts must prove that the class uses one direct record.
This declaration support does not expand optimized field access or constructor calls.

An optional nested array of class instances also crosses the group. Omitted and
explicit null arguments select the same branch. Supplied arrays retain their
identity and expose mutation through an alias; an empty array stays empty.
The exported parameter and return types use checked array runtime identities.
Arrays with unsupported elements, such as Dynamic or Iterator, remain rejected.

Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=module_structural_signature \
  bash scripts/test-portable.sh
```

The runner compiles and executes OCaml output. The additional check compares
the independent expected output with upstream Haxe eval.
Missing signatures and eager recursive initialization remain covered by
`OcamlFunctionModuleCheckTest` and `module_recursive_functions`.
