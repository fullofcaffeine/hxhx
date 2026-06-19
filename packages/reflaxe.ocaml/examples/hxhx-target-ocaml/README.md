# hxhx-target-ocaml

Minimal native-lane smoke example for `hxhx --ocaml`.

It exists to keep the `hxhx` entrypoint and `reflaxe.ocaml` target wiring honest:
the example compiles, builds under OCaml tooling, runs, and diffs against
`expected.stdout`.

Run it from the repo root:

```bash
npm run test:examples
```

