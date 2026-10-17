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
runs C++ and compares all six lines. The expected output remains an independent
positive contract. Passing this
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

The six-line candidate contract remains unchanged. The bundled C++ provider
now uses explicit word storage at the Dynamic boundary, while ordinary class
predicates retain their descriptor checks. `haxe_ocaml-sp2zl` remains open for
combined validation, publication, and merge.

`transport/Main.hx` retains a separate 63-line hxcpp expectation. It checks
signed limits, both words after recovery, strings, arrays of erased values,
once-only effects, and unrelated predicate inputs. Its native observer forces
collection and runs ASan/UBSan at O0 and O2. Run it directly with:

```sh
haxe test/m14_cpp_int64_transport_test.hxml
```

The ordinary class-value test command also runs this transport contract. The
`override` fixture uses a complete project-owned copy of the provider with one
private helper replaced by an authored Haxe body. It proves that the replacement
keeps its body and classpath priority. Direct printing of the abstract Int32 words is not
part of this check; `Std.string` observes their exact decimal values.

The compiler keeps Int64 arithmetic in Haxe. It uses integer Dynamic storage
for the observed small range, and an immutable native word pair otherwise.
That pair has no ordinary class identity. Checked integer recovery is supported;
other Dynamic coercions and erased Int64 equality still report unsupported
operations. This test does not establish complete Int64 compatibility.

`representation/detail/Main.hx` records finer upstream observations in
`observed.json`: exact Type.typeof constructor, public class name, Int64 and
Int membership, then separate recovery observations. Wide native Int64 values
report TClass but have no public class. Float 256 passes the Int predicate and
fails the Int64 predicate. Use explicit Dynamic parameters here: inferring a
local from later typed recovery can convert the input before observation.
The detail probe is upstream evidence, not a claim that all reflection and
coercion operations are supported by the candidate.

Before changing numeric storage or predicates, apply
[`FLOAT_NUMERIC_REVIEW_GATE.md`](../../../docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md).
Keep nominal object tests and downcasts consistent with their actual storage.
These observations do not change Full1 or project-readiness claims.
