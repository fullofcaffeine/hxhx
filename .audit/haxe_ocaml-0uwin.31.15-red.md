# Expected red state: Array indexed searches

The focused call-plan fixture first named `IndexOf` and `LastIndexOf` before
the closed standard-Array operation model admitted either operation.

Command:

```text
npm run test:reflaxe-ocaml:call-plan
```

Expected failure:

```text
CallPlanFixture.hx:1031: Unknown identifier: IndexOf
CallPlanFixture.hx:1031: Unknown identifier: LastIndexOf
CallPlanFixture.hx:1679: OcamlStandardArrayOperation has no field IndexOf
CallPlanFixture.hx:1680: OcamlStandardArrayOperation has no field LastIndexOf
```

This was the intended failure. It showed that the smallest faithful planning
contract could not pass merely because the late OCaml printer still recognized
the source method names.

During the vertical tracer, an independent second red state found an existing
runtime-boundary defect. A Haxe call that supplied `null` for the optional
start index generated the `HxRuntime.hx_null` carrier, but `HxArray.indexOf`
still required an OCaml `int`. The generated OCaml therefore failed to type
check. The runtime adapter now accepts the typed Haxe optional carrier, checks
the null sentinel, and returns a concrete `int` before search logic runs.
