# Function arguments and results through the shared OCaml target

This regression requires both compiler hosts to copy ordinary function arguments and results into the same target facts.
The authored functions return Int, Bool, and String values. One function copies its first argument through a local and ignores its second argument.
Other cases check nested calls, shadowed locals, explicit Void returns, and names that collide with generated temporaries or OCaml keywords.
Conditional cases select Int, Bool, and String results. They cover nested calls and locals declared separately inside each branch.
Both ternary expressions and terminal returned if-expressions must produce matching facts through the two hosts.

Run the contract from the repository root:

```sh
node_modules/.bin/haxe test/reflaxe_ocaml_shared_function_values/test.hxml
```

The test first runs an independent result observer with upstream Haxe.
It compares the complete function inventory, canonical identities, and OCaml syntax from both adapters.
It then compiles the whole application and an independent OCaml observer.
The observer calls the emitted functions with different values, including Unicode and an embedded zero byte.
It also supplies effectful argument functions to independently check the lowerer's left-to-right, exactly-once call behavior.
An effectful condition and two alternative functions prove that the condition runs once and only the selected branch runs.
Typed-module identities must remain unchanged after adaptation. Corrupt parameter identities, argument types, and return types must fail validation.
Conditional validation also rejects wrong child paths, a non-Boolean condition, mismatched results, and locals read from the other branch.
Both adapters reject optional, defaulted, rest, generic, nullable Bool, and Float signatures until their semantics enter the shared contract.
Nullable Int has its own required regression in `test/reflaxe_ocaml_shared_nullable_values`.

The focused regression is included in `npm run test:reflaxe-ocaml:target-definition`.
Run the complete stock-Haxe preprocessing and native runtime check with:

```sh
npm run test:reflaxe-ocaml:shared-function-values
```

The stock check requires the shared function marker to survive preprocessing, builds the generated Dune project, and links the independent observer against its runtime.
This function support is a prerequisite for the native method-call failure tracked by `haxe_ocaml-i1c2c` and PR #92.
The original nullable instance-call test remains required and unchanged.

This test runs the Haxe-authored frontend under upstream Haxe's interpreter.
It does not prove a rebuilt native compiler, nullable arguments, early returns, instance construction, receiver capture, or the complete shared-target migration.
Those requirements remain with their existing tasks and owners.
