# Inline constants in a module with several classes

Haxe substitutes inline constants at their uses. The target must not allocate
mutable storage for them. Previously, retaining a second class in the same
module created extra cells before the classes. Recursive module validation
then rejected those allocations.

This fixture retains two classes and a function dependency cycle. It checks
String, Int and Bool constants, verifies that no mutable cells were planned,
and compares native output with independent expectations and Haxe/eval.

Run `PORTABLE_FIXTURE_ALLOWLIST=module_inline_static_storage bash scripts/test-portable.sh`
from the repository root.
