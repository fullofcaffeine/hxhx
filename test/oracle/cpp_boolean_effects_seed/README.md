# Boolean short-circuit effects

The program observes whether each right operand runs. False AND and true OR must
skip it. True AND and false OR must execute it once. Nested expressions must
preserve the result.

```sh
haxe -cp test/oracle/cpp_boolean_effects_seed -main Main --interp
haxe test/m14_cpp_managed_boolean_test.hxml
```

The authored program produces no output on success and throws on a failed
assertion. The native test prints its pass marker.
