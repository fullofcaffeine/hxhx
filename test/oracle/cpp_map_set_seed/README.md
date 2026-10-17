# Native Map mutation

`MapWrite.hx` inserts values through complete authored methods. The callbacks
make receiver, key, and value evaluation observable. `Main.hx` specifies the
upstream output in `expected.cpp.stdout`.

Run the candidate regression with `npm run test:m14:cpp-map-set`. It checks
exact call ownership and rejects copied or mutated call facts. An independent
C++ observer then invokes each complete method with collection at every
allocation and during callbacks. Both O0 and O2 builds use address and
undefined-behavior sanitizers.

The observer checks operand order, exceptions before insertion, replacement of
an existing key, string and integer keys, object identity, and reference
retention. Integer values widen exactly into Float storage, including both
32-bit limits. After the methods return, collection must remove all temporary
objects and roots.

`Normal.hx` reproduces the original product failure: create a Boolean Map, call
`set`, then print `get`. The test builds and executes this program through
`CppTargetCore`, the normal native target, and compares it with upstream
interpreter output. This also checks production method planning.

For the native upstream reference, use Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_map_set_seed -main Main -cpp .tmp/cpp-map-set-reference
.tmp/cpp-map-set-reference/Main > .tmp/cpp-map-set-reference.stdout
diff -u test/oracle/cpp_map_set_seed/expected.cpp.stdout .tmp/cpp-map-set-reference.stdout
```

These checks cover the listed Map operations. They do not establish full
standard-library or release readiness. README Goals status is unchanged.
