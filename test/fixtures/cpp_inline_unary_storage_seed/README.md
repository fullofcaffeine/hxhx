# Inline unary storage

Run `haxe test/m14_cpp_inline_unary_storage_test.hxml` from the repository root.
Upstream Haxe and a separate native observer compare all 19 values with
`expected.stdout`. Native builds use O0/O2, strict warnings, ASan/UBSan, and
collection before every managed allocation.

The fixture covers prefix and postfix results, caller mutations, simple writes,
an update inside a helper, and effectful field and indexed receivers. The final
case changes the destination during the right-hand side. Its result must use
the old value captured before that change.

The native compiler loads the real Array provider and retains its dependency
graph. Its declarations contain no retained enum constants. The observer requires
only the program's scalar storage to remain after collection; every temporary
object and array must be collected.
The larger original unary fixture remains a separate acceptance requirement.
