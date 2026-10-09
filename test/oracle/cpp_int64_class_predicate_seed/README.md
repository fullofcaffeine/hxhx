# Real Int64 runtime predicate

This program calls `haxe.Int64.isInt64` through its real standard-library
provider. Two Int64 values return true. Null, a String, and an Array return
false. Native C++ also accepts the ordinary Int value 2; the interpreter does
not. Dynamic stays at the predicate's public input boundary.

Upstream Haxe 4.3.7 interpreter output is retained in `expected.interp.stdout`.
The hxcpp 4.3.2 native output is retained in `expected.cpp.stdout`. These are
black-box observations, not implementation copies.

```sh
haxe -cp test/oracle/cpp_int64_class_predicate_seed/src -main Main --interp
haxe -cp test/oracle/cpp_int64_class_predicate_seed/src -main Main -cpp /tmp/int64-predicate
/tmp/int64-predicate/Main
HXHX_M14_SMOKE_GROUP=int64_predicate haxe test/m14_cpp_runtime_class_value_test.hxml
```

The candidate test requires the real Int64 and Std modules, then compiles and
runs C++ and compares all six lines. The expected output remains a positive
contract even while the candidate compiler cannot yet pass it. Passing this
test does not establish complete Int64 arithmetic or Full1 compatibility.
