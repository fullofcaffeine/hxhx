# Expected-red record: standard Array mutation calls

## Intended behavior gap

The focused call-plan fixture referred to `Push` in the closed
`OcamlStandardArrayOperation` model before the compiler implemented that
operation. This made the test ask for the missing compiler-owned behavior at
the lowest faithful layer.

## Command

```text
npm run test:reflaxe-ocaml:call-plan
```

## Expected failure

The Haxe compiler stopped at `CallPlanFixture.hx:1643` with
`OcamlStandardArrayOperation has no field Push`.

That was the intended failure: the test setup and existing Array operations
were already valid, but the new mutation operation did not yet exist. The
subsequent implementation made this same focused suite green before the wider
inspection and build/run checks were used.
