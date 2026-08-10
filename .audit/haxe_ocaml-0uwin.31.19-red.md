# Expected red state: nested String callback result

The Array behavior tracer uses a named function that returns an `Int -> String`
closure. Haxe's typed callback body contains a generated String result local.
That local is assigned before its first read, so generated OCaml does not need
an initial null value.

Command:

```text
npm run test:m6:array
```

Expected failure:

```text
OCaml final runtime-use reconciliation failed: missing final runtime use
string-default:...makeMapCallback...:local-default:...
```

The failure is correct and useful. It proves that the compiler authorized a
private String null sentinel which did not reach final output. The fix must
remove the unnecessary authorization. It must not weaken reconciliation.
