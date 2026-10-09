# Recover an array from Dynamic

This fixture records native C++ conversion behavior observed with Haxe 4.3.7
and hxcpp 4.3.2. It deliberately uses Dynamic only at the boundary under test.

Run the managed target contract from the repository root:

```sh
HXHX_M14_SMOKE_GROUP=array_recovery haxe test/m14_cpp_runtime_class_value_test.hxml
```

The managed target does not yet pass this contract. Keep it alongside the
original erased-array alias case; neither replaces the other.

Native C++ returns null when a record or scalar is assigned to Array<Bool>.
It preserves the original Boolean array when that array passes through Dynamic.
Converting an integer array produces Boolean elements in separate storage:
zero becomes false, nonzero integers become true, and mutation does not change
the original integer array. Empty Boolean and Dynamic arrays retain aliases;
empty integer arrays do not. Mixed Boolean/integer Dynamic arrays retain
aliases while Boolean reads convert the values. Appending an integer through
the original Dynamic array is visible through its recovered Boolean view.

The interpreter behaves differently. It preserves the integer elements and
their alias, and wrong-family access fails after assignment. Keep these two
expectations separate: expected.cpp.stdout is the native target contract;
expected.eval.stdout records the interpreter observation.

To reproduce the reference behavior, run this source with the pinned upstream
compiler using --interp, then compile it with -cpp and run the resulting Main
executable. Compare each stdout with its corresponding file. Do not copy
upstream runtime or compiler implementation to satisfy these observations.

The current common array payload does not retain enough representation facts
to choose between alias-preserving recovery and element conversion. A physical
ArrayPayload check alone cannot implement this contract. Broader numeric,
nullable, object, and other mixed-element cases still need explicit evidence;
this fixture does not establish their semantics or Full1 readiness.
