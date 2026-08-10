# Expected red state: Array slice

The focused call-plan fixture first named `Slice` and `SliceDefault` before the
closed standard-Array operation model admitted either operation.

Command:

```text
npm run test:reflaxe-ocaml:call-plan
```

Expected failure:

```text
CallPlanFixture.hx:1033: Unknown identifier: Slice
CallPlanFixture.hx:1034: Unknown identifier: SliceDefault
CallPlanFixture.hx:1687: OcamlStandardArrayOperation has no field Slice
CallPlanFixture.hx:1688: OcamlStandardArrayOperation has no field SliceDefault
```

This showed that the smallest faithful planning contract could not pass merely
because the late OCaml printer still recognized the source method name.

The first vertical tracer also deliberately tried a null required position.
The static Haxe compilation rejected it before target generation with
`null can't be used as basic type Int`. That case was removed, together with an
unneeded attempt to widen the native position parameter. The supported slice
contract remains exact: required `Int` position and optional `Null<Int>` end.
