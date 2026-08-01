# hxhx-target-ocaml

Minimal delegated target smoke example for `hxhx --ocaml-eval`.

The example runner invokes the already-installed upstream Haxe compiler through
the `hxhx` compatibility entrypoint, then lets `reflaxe.ocaml` generate the
target. It compiles the generated OCaml, runs it, and compares stdout. This
proves the delegated target route; it does not prove the separate native
Stage3 target path.

Run it from the repo root:

```bash
npm run test:examples
```
