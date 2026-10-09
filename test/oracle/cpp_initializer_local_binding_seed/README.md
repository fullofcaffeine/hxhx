# Initializer local bindings

Each field initializer uses `int` and `int_` as separate local variables. One initializer stores integers; the other stores strings. The constructor also has a parameter named `int`.

The program prints the constructor argument, the numeric field, and the string field. The expected output is `99`, `7`, and `left:right`, on separate lines. Upstream Haxe 4.3.7 confirms this behavior.

Run the upstream reference:

```sh
haxe -cp test/oracle/cpp_initializer_local_binding_seed/src -main Main --interp
```

Run the C++ compiler and native observer:

```sh
haxe test/m14_cpp_initializer_local_binding_integration_test.hxml
```

The native test must compile and execute the generated program. Distinct variable declarations alone do not prove that each read uses the correct binding. This fixture supports the local-ownership migration; it does not establish broader target readiness.
