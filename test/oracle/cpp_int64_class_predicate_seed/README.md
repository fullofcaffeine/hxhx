# Real Int64 runtime predicate

This program calls `haxe.Int64.isInt64` through its real standard-library
provider. Two Int64 values return true. Null, a String, and an Array return
false. Native C++ also accepts the ordinary Int value 2; the interpreter does
not. Dynamic stays at the predicate's public input boundary.

Upstream Haxe 4.3.7 interpreter output is retained in `expected.interp.stdout`.
The hxcpp 4.3.2 native output is retained in `expected.cpp.stdout`. These are
black-box observations, not implementation copies.

```sh
haxe -cp test/oracle/cpp_int64_class_predicate_seed/src -main Main --interp
haxe -cp test/oracle/cpp_int64_class_predicate_seed/src -main Main -cpp /tmp/int64-predicate
/tmp/int64-predicate/Main
HXHX_M14_SMOKE_GROUP=int64_predicate haxe test/m14_cpp_runtime_class_value_test.hxml
```

The candidate test requires the real Int64 and Std modules, then compiles and
runs C++ and compares all six lines. The expected output remains a positive
contract even while the candidate compiler cannot yet pass it. Passing this
test does not establish complete Int64 arithmetic or Full1 compatibility.

## Numeric representation boundary

The separate `representation/Main.hx` probe records 34 inputs with both
`haxe.Int64.isInt64(value)` and `Type.typeof(value)`. Expected files retain
independent observations from upstream Haxe 4.3.7 with hxcpp 4.3.2 and from eval.
Each line contains the case name, predicate result, and observed value category.
`other` groups the categories outside Null, Int, Float, and Bool.

C++ reports `255.0` as Int and accepts it, but reports `256.0` as Float and
rejects it. It also reports `Int64.ofInt(0)` as Int. The interpreter preserves
different categories. These results show why a numeric range check alone cannot
define the predicate. They do not establish behavior on every hxcpp version or
platform.

Run the same source through each upstream target:

```sh
haxe -cp test/oracle/cpp_int64_class_predicate_seed/representation -main Main --interp
haxe -cp test/oracle/cpp_int64_class_predicate_seed/representation -main Main -cpp .tmp/int64-representation
.tmp/int64-representation/Main
```

Compare stdout with the corresponding `representation/expected.*.stdout` file.
The C++ observations were collected on macOS arm64.

Candidate status: **known_divergence**, tracked by `haxe_ocaml-sp2zl`. The existing
six-line native candidate test remains unchanged and still requires a fix.
The representation probe is upstream evidence, not a passing candidate test.

Before changing numeric storage or predicates, apply
[`FLOAT_NUMERIC_REVIEW_GATE.md`](../../../docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md).
Keep nominal object tests and downcasts consistent with their actual storage.
These observations do not change Full1 or project-readiness claims.
