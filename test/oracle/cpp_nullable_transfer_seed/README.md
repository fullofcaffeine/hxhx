# Nullable integers entering native Int storage

This program checks null and present values at ten C++ transfer boundaries:
local initialization and assignment, static and instance fields, array elements,
static and instance arguments, returned values, constructor arguments, and captured writes.
Each supplied expression must run once. Conversion must leave the nullable source unchanged.

Upstream Haxe 4.3.7 with hxcpp 4.3.2 converts null to zero at these native Int
boundaries. A separate printing probe confirms the target difference: upstream
interp preserves null through the same seven basic transfers. Do not use interp
as the expected runtime for this C++ assertion program.

Run the candidate contract, including forced collection and O0/O2 sanitizers:

```sh
npm run test:m14:cpp-nullable-transfer
```

Run the independent upstream native assertions from a Haxe 4.3.7 environment
with hxcpp 4.3.2 installed:

```sh
haxe -cp test/oracle/cpp_nullable_transfer_seed -main Main -cpp .tmp/upstream-nullable-transfer
.tmp/upstream-nullable-transfer/Main
```

Successful execution prints nothing and exits zero. The candidate observer also
requires zero temporary roots and exactly one retained program storage object.
The companion declared-local test checks that later assignments cannot widen
an Int local to Null<Int> before emission.

This contract excludes Boolean, Float, Dynamic, and abstract conversions.
It does not establish complete constructor defaults or Full1 compatibility.
