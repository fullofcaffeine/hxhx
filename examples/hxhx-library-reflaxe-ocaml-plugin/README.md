# hxhx library reflaxe.ocaml plugin

This example proves that `hxhx` can activate a library-provided compiler extension
while compiling a small `reflaxe.ocaml` program.

It exercises:

- `--library`/library metadata resolution,
- plugin-provided classpath injection,
- macro hook execution,
- and OCaml output that is built and run by the example harness.

Run it from the repo root:

```bash
npm run test:examples
```

