# Escaping recursive counter

The program creates a recursive counter and returns it. Repeated calls must share
the captured count after the creator exits. The complete expected output is:

```text
true
10
3
5
```

```sh
haxe -cp test/oracle/source_named_function_seed/src -main Main --interp
haxe test/m14_source_named_function_test.hxml
haxe test/m14_cpp_managed_closure_abi_integration_test.hxml
```

The first command supplies upstream Haxe behavior. The second exercises the normal
C++ target and owns the task's final acceptance. The third exercises the managed
program emitter with real Array and Sys providers, forced collection, and native
sanitizers. It uses this exact source and expected output, including the record
array, switch, loop, String comparison, named recursion, and two counter calls.

Passing the managed-emitter check does not close `haxe_ocaml-9jezt`. The normal
target still needs the managed-storage cutover, broader runtime evidence, and review.
