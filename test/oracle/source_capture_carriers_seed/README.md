# Captures across arrays and objects

Array aliases must observe the same element mutation. An escaped callback and its copy must also share the object captured by that callback.
The object stores the callback, creating a cycle that the eventual C++ ownership implementation must collect after all external roots disappear.

The authored output is 9, 11, and 12, on separate lines. The output proves aliasing and callable behavior; it cannot prove cycle collection.
Run the upstream reference with `npm exec -- haxe -cp test/oracle/source_capture_carriers_seed/src --run Main`.
Run the current candidate with `npm exec -- haxe test/m14_cpp_capture_carriers_test.hxml`.
Native failures retain artifacts under `.tmp/source-capture-carriers`. Cleanup and sanitizer observations remain separate requirements of `haxe_ocaml-9jezt`.
