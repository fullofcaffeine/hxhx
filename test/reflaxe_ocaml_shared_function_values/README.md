# Function arguments and results through the shared OCaml target

This regression requires both compiler hosts to copy ordinary function arguments and results into the same target facts.
The authored functions return Int, Bool, and String values. One function copies its first argument through a local and ignores its second argument.

Run the contract from the repository root:

```sh
node_modules/.bin/haxe test/reflaxe_ocaml_shared_function_values/test.hxml
```

The test first runs an independent result observer with upstream Haxe.
It compares the complete function inventory, canonical identities, and OCaml syntax from both adapters.
It then compiles the whole application and an independent OCaml observer.
The observer calls the emitted functions with different values, including Unicode and an embedded zero byte.
Typed-module identities must remain unchanged after adaptation.

This regression is currently red: both adapters admit only static, zero-argument Void functions.
It is an explicit prerequisite for the native method-call failure tracked by `haxe_ocaml-i1c2c` and PR #92.
It is not included in a passing aggregate command until the shared target implements its contract.
The original nullable instance-call test remains required and unchanged.

This test runs the Haxe-authored frontend under upstream Haxe's interpreter.
It does not prove a rebuilt native compiler, nullable arguments, early returns, instance construction, receiver capture, or the complete shared-target migration.
Those requirements remain with their existing tasks and owners.
