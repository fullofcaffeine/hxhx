# build-macro

Small `@:build` macro example for `reflaxe.ocaml`.

It proves that the example harness can compile a Haxe program through the current
`hxhx --ocaml-eval` path, execute a build macro, produce OCaml, build it with
dune, run the executable, and compare its output with `expected.stdout`.

Run it from the repo root:

```bash
npm run test:examples
```

This example also has example-specific checks in `test.sh`. The example runner
executes them after compiling, running, and diffing `expected.stdout`.
