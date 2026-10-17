# Native Array.push reference

This independently authored probe records Haxe 4.3.7 with hxcpp 4.3.2 on macOS
arm64. Compile and run it with the pinned upstream toolchain:

```sh
haxe -cp test/oracle/cpp_managed_array_push_seed/src -main PushProbe -cpp /tmp/array-push-reference
/tmp/array-push-reference/PushProbe
```

Compare stdout with `expected.cpp.stdout`. The probe covers receiver/argument
effects, replacement of the source array during argument evaluation, returned
length, discarded calls, empty arrays, and mutation through a recovered Boolean
view of a Dynamic array. Dynamic is confined to that explicit boundary.

Run `haxe test/m14_cpp_managed_array_read_test.hxml` for the candidate regression.
It checks authored source and native sanitizer observers. This reference probe
does not claim complete compilation of its source with the candidate or full
target compatibility.
