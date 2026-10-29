# Native Array.push method values

This fixture saves `array.push` in a variable, changes the source array variable,
and calls the saved method. The saved method must retain its original array and
return the new length. It also checks argument side effects and an array whose
elements are functions.

Haxe 4.3.7 with hxcpp 4.3.2 produced `expected.stdout`:

```sh
haxe -cp test/oracle/cpp_array_push_value_seed -main Main -cpp .tmp/upstream-array-push
.tmp/upstream-array-push/Main
```

The second output line compares two reads of the same array's `push` method.
Native C++ returns `true`; the Haxe interpreter returns `false`. All other output
lines agree. `expected.eval.stdout` records the interpreter result separately.

Run the local compiler regression with:

```sh
haxe test/m14_cpp_array_push_value_test.hxml
```

The test uses real standard-library declarations, builds and runs the native
program, and rejects copied or stale method selections. `Stress.cpp` runs the
generated program with collection enabled at every allocation, at both `-O0`
and `-O2` with address and undefined-behavior sanitizers. Two independent heaps
must produce the same output and release all temporary arrays and functions.
The fixed remaining allocation count comes from the listed standard-library
values, rather than from the observed count after the test.
