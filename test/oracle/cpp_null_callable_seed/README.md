# Calling a null function

Run `haxe -cp test/oracle/cpp_null_callable_seed -main Main --interp` with upstream
Haxe 4.3.7. The argument increments the counter before the call fails. The output
must match `expected.stdout`. Neko produces the same result.

The managed C++ runtime previously rejected null during callable selection,
before arguments ran. It now retains the selected value and checks it at invocation.
`test:m14:cpp-managed-closure-abi` checks generated argument sequencing against this
expectation. `test:m14:cpp-managed-heap -- ManagedCallableTest` checks the primitive.
These component tests do not prove normal C++ source emission; haxe_ocaml-9jezt
still owns that integration.
