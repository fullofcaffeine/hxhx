# Expected red state: Array sort

The focused call-plan fixture first named `Sort` before the closed
standard-Array operation model admitted it.

Command:

```text
npm run test:reflaxe-ocaml:call-plan
```

Expected failure:

```text
CallPlanFixture.hx:1035: Unknown identifier: Sort
CallPlanFixture.hx:1691: OcamlStandardArrayOperation has no field Sort
```

This showed that the smallest faithful planning contract could not pass merely
because the late OCaml printer still recognized the `sort` source field.
