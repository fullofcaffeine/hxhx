# Null storage in native C++

Run `haxe test/m14_cpp_managed_null_test.hxml` from the repository root.

The source distinguishes null from empty text and present nullable integers.
It checks local, field, constructor, call, closure-result, static, and array
transfers. A generic abstract backed by String must also preserve null.
Array comprehensions copy null elements without changing their values.
The test loads the real Array declaration through the production module loader.

Upstream Haxe executes the source assertions first. The normal C++ target then
builds and runs the same program. A native observer forces collection before
each allocation under address and undefined-behavior sanitizers, at `-O0` and `-O2`.
It reads the exact completion field and checks that temporary objects were collected.
The completion flag prevents an empty or skipped entry body from passing.

Negative controls reject null transfers to non-nullable scalar storage, removal
of null from `Null<Int>`, and implicit integer-to-String conversion.
The cast-plan test separately rejects null storage for scalar-backed abstracts.

The element-count observer uses a closure. Ordinary method loops remain tracked
by `haxe_ocaml-86u4u`; its original failing source is preserved in the integration audit.
Checked casts, numeric coercions, arbitrary Dynamic conversion, and general
object equality remain separate contracts. README goal estimates are unchanged.
