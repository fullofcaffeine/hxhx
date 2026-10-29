# Results from branches and switches

The program selects values through `if` and `switch`, including an early return
inside a nested function. Only the selected branch produces a value. The switch
input executes once. A default arm remains the fallback even when written first.

```sh
haxe -cp test/oracle/cpp_managed_control_value_seed/src -main Main --interp
haxe test/m14_cpp_managed_closure_abi_integration_test.hxml
```

Upstream Haxe 4.3.7 must match `expected.stdout`. The native fixture emits the
same eight methods through the production managed function emitter. Independent
C++ callbacks collect before returning arrays or throwing. Native checks observe
both branch outcomes, each switch arm, String null, nested switches, early
returns, and loop exits through a switch.

Shared lowering creates result temporaries and assigns them only on paths that
finish normally. `LocalSlot` roots such a result and rejects reads before its
first assignment. Assigned null remains a real value. This runtime check does
not authorize uninitialized source variables based on their names.

Literal Int, Bool, and String patterns, String null, alternatives, and default
are covered. Binding and extractor patterns need separate typed storage plans.
This fixture does not establish the normal C++ target cutover or full pattern
matching support.
