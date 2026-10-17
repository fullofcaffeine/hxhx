# Native array assignment reference

This independently authored probe records Haxe 4.3.7 with hxcpp 4.3.2 on macOS
arm64. Compile and run it with the pinned upstream toolchain:

```sh
haxe -cp test/oracle/cpp_managed_array_write_seed/src -main WriteProbe -cpp /tmp/array-write-reference
/tmp/array-write-reference/WriteProbe
```

Compare stdout with `expected.cpp.stdout`. The probe checks expression and
discarded assignments, operand order, negative indices, growth defaults, and
writes through a Boolean view of a Dynamic array. The Dynamic values are confined
to the explicit erased-array boundary under observation.

The candidate regression command is `haxe test/m14_cpp_managed_array_read_test.hxml`.
It covers the write handler through authored source and native sanitizer observers.
This reference probe is not itself a claim that its complete source compiles with
the candidate, or that the observed ordering applies to other upstream targets.
