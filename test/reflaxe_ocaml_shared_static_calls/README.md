# Static calls through the shared OCaml target

This fixture compiles a chain of static methods in the same class. Each method
takes no arguments and returns `Void`. Both compiler hosts copy the resolved
callee into the same immutable target facts. The shared target produces the
OCaml call and checks that every callee has an admitted body.

Run the focused comparison from the repository root:

```sh
node_modules/.bin/haxe test/reflaxe_ocaml_shared_static_calls/test.hxml
```

The fixture compares stock-Haxe and native-host function identities and syntax.
It checks call order, unsupported signatures, missing callees, and foreign
owners. It then builds and runs the emitted OCaml application. Methods named
`type` and `ignore` test keyword escaping and standard-library name collisions.
A local named `hx_type` must not intercept the call to `type`.

Run the stock compiler through Reflaxe preprocessing and native execution too:

```sh
taskpolicy -b nice -n 10 node scripts/hxhx/with-heavy-run-lease.js \
  --label shared-static-calls \
  -- bash scripts/ci/reflaxe-ocaml-shared-static-calls-test.sh
```

On hosts without `taskpolicy`, omit that command. The stock test requires the
shared function marker to survive preprocessing. Both applications must exit
successfully with empty output. This proves compilation and termination; these
methods have no externally visible effects.

The native-host fixture runs the Haxe-authored parser and typer under the Haxe
interpreter. It does not rebuild the native compiler executable or prove full
native workload acceptance. Arguments, returned values, cross-class calls,
computed receivers, and calls in field initializers remain outside this contract.
The native adapter currently admits bare method references only.
