# Neutral C++ callable signatures

This fixture calls the fast and generic fallback methods of a neutral assertion support class.
Both authored bodies return false, so the observer tests signature adaptation without claiming assertion behavior.

Calls pass integers and absent optional values. The fast method's parameter names also collide after C++ keyword sanitization.
The effectful argument must run exactly once. The native test loads the installed `haxe.PosInfos` declaration before typing.

The fixture also calls and rebinds assignable assertion hooks. Separate counters observe callback construction and execution.
An ordinary static dynamic function changes from addition to multiplication after rebinding.
A framework-neutral `Dynamic -> Dynamic` callback must return integer, boolean, string, and null values without converting them to strings.
These checks cover callable storage and value transport; the default assertion hooks retain neutral bodies.

Run upstream behavior:

```sh
haxe -cp test/oracle/cpp_neutral_callable_seed/src -main Main --interp
```

Run generation, native compilation, and the independent stdout comparison:

```sh
haxe test/m14_cpp_neutral_callable_integration_test.hxml
```
