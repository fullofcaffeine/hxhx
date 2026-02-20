# Examples

This folder now contains examples that are mainly about `hxhx` behavior itself
(target presets, macro-host/plugin integration, and compiler wiring).

`reflaxe.ocaml`-focused examples live in:

`packages/reflaxe.ocaml/examples/`

The test runner checks both roots.

Run all examples from the repo root:

```bash
npm run test:examples
```

Some examples are intentionally heavier and are **skipped** by `test:examples`.
Run those with:

```bash
npm run test:acceptance
```

## Included examples

- `hxhx-target-ocaml`: runs a tiny app through `hxhx --target ocaml`.
- `hxhx-library-reflaxe-ocaml-plugin`: Stage3 plugin fixture (`--library`, macro hooks, classpath injection).
- `hxhx-js-todoapp`: lix-first JS todo app (`coconut.ui`, `tink_web`, `tink_sql` schema types) compiled via `hxhx --target js`.
