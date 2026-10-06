# String and Boolean exception handlers

Run `npm run test:m14:cpp-string-catch` to compile and execute the complete source
with the real exception providers. The same program runs with forced collection
and address and undefined-behavior sanitizers at `-O0` and `-O2`.

The assertions cover raw and wrapped values, both handler orders, unmatched
wrappers, null, subclasses, nested wrappers, replacement exceptions, and mutable
catch variables retained by closures after their handler returns. The native
observer also checks that temporary roots and allocations are released.

The upstream reference uses Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_string_catch_seed -main Main \
  -cpp .tmp/cpp-string-catch-reference -D HXCPP_COMPILE_THREADS=2
.tmp/cpp-string-catch-reference/Main
```

Successful execution produces no output. Native wrapper selection has target-specific
behavior, so interpreter results do not replace this native reference.
Other catch categories remain open under `haxe_ocaml-qrk0u`.
