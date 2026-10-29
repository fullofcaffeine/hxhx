# Enum payload comparison

Run `haxe test/m14_cpp_enum_equality_test.hxml` for the complete authored programs.
The test compares native output with Haxe 4.3.7/hxcpp 4.3.2 observations.
It also runs both programs at O0 and O2 with nonrecovering address and
undefined-behavior sanitizers. Every allocation can trigger collection.

`EnumPayloadProbe.hx` records 27 payload values and both operators independently.
For example, `Payload(1)` equals `Payload("1x")` on the native reference.
Reversing these operands produces false. This conversion differs from ordinary
Dynamic equality and from the interpreter, whose observations remain separate.

A String payload can call the right object's `toString()`. The probe records
the call count, thrown String, null return, array conversion and enum conversion.
The compiler must retain these implicit method calls before it finishes linking.
An ordinary Int comparison does not enable that conversion family.

`FloatTextProbe.hx` records 22 native text results used by String-left comparisons.
These include signed zero, NaN, infinities, precision boundaries, exponent
thresholds, the smallest subnormal, and the largest finite Float. The native
formatter preserves the observed 15-digit spelling without changing stored bits.
Parsing, JSON, serialization and arithmetic keep their existing owners.

The native value observer in `DynamicEqualityObserver.cpp` checks the payload
matrix through generated comparison functions. It also checks distinct enum
descriptors, constructor ordinals, NaN self-comparison, nested conversion,
collection during callbacks, exception propagation and root cleanup.

Reproduce upstream observations with:

```sh
node scripts/hxhx/cpp-dynamic-equality-oracle-seed.js --payload-only
```

The command requires Haxe 4.3.7 and hxcpp 4.3.2. Without the option, it also checks
the original 69-value matrix. Each native fixture has a separate build directory.

The parent fixture retains the upstream non-null/right-null payload crash.
The candidate reports an explicit unsupported diagnostic for that case.
This is unfinished compatibility work under `haxe_ocaml-rirak`, not a promised
crash or an invented equality result. README readiness remains unchanged.
