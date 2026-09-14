This fixture checks enum-abstract constants and a call to an abstract instance
method. String values without initializers use their field names. Int values
continue from the preceding value. Both `var` and `final` declarations work.
The observer also checks receiver and argument evaluation order, omitted and
explicit-null defaults, and a typed try/catch expression that returns the thrown
string. The try/catch check protects the indexed test harness used by the broader
Neko smoke test; it does not prove exception-stack support.

`M14NekoTypedProgramProjectionIntegrationTest` compiles and runs the same source
through upstream Haxe and both Neko output layouts, then compares
`expected.stdout`. It also checks that the unused abstract method is absent
from generated output. Run the owning test with:

```sh
haxe -cp packages/hxhx-core/src -cp test --run M14NekoTypedProgramProjectionIntegrationTest
```

The runtime check requires `haxe`, `nekoc`, and `neko`. It does not prove all
constant expressions, abstract receiver writes, or complete Neko compatibility.
