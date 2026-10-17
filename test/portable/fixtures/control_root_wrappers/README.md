This fixture checks metadata around a function body and a direct return statement.
The early branch must exit with its value; the final return must complete normally.
Metadata must not add a private runtime return signal or lose an existing early return.

Run the upstream behavior check from the repository root:

```sh
haxe -cp test/portable/fixtures/control_root_wrappers/src -main Main --interp
```

Run native generation, compilation and exact output comparison:

```sh
PORTABLE_FIXTURE_ALLOWLIST=control_root_wrappers bash scripts/test-portable.sh
```

The control-plan fixture separately checks exact typed-node ownership and parentheses.
This fixture does not change README Goals readiness.
