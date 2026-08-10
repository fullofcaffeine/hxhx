# Expected red state: Array map and filter

The focused call-plan fixture named `Map` and `Filter` before the closed
standard-Array operation model admitted them.

Command:

```text
npm run test:reflaxe-ocaml:call-plan
```

Expected failure:

```text
CallPlanFixture.hx:1696: OcamlStandardArrayOperation has no field Map
CallPlanFixture.hx:1697: OcamlStandardArrayOperation has no field Filter
```

This result proves that the focused semantic plan cannot pass only because the
late OCaml builder still recognizes the two source method names.
