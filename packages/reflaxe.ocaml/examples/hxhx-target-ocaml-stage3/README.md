# hxhx-target-ocaml-stage3

Minimal Stage3 smoke example for `hxhx --hxhx-stage3` with `reflaxe.ocaml`.

It is intentionally small: the point is to prove that the native Stage3 path can
select the OCaml target, emit an executable, run it, and compare stdout without
depending on a larger demo app.

Run it from the repo root:

```bash
npm run test:examples
```

