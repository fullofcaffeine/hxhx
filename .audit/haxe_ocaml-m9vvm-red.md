# Expected-red evidence: early-return Eof assertion

Command:

```text
PORTABLE_FIXTURE_ALLOWLIST=early_return PORTABLE_JOBS=1 bash scripts/test-portable.sh
```

Observed failure before the test-policy correction:

```text
Error: the instance result slice accidentally changed the separate Eof throw boundary
```

The generated OCaml built and the executable produced its expected output before
this assertion failed. The lowering report showed one admitted
`haxe.io.Eof` nominal-class throw from `OcamlStdioInput.readBytes`, which is the
behavior authorized earlier by commit `10df8338a`. The stale fixture still
expected that throw family to be blocked.
