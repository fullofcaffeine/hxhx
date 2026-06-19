# Examples

This folder now contains examples that are mainly about `hxhx` behavior itself
(lane selectors, macro-host/plugin integration, and compiler wiring).

`reflaxe.ocaml`-focused examples live in:

`packages/reflaxe.ocaml/examples/`

The test runner checks both roots.

Run all examples from the repo root:

```bash
npm run test:examples
```

When adding or changing an example, also run the fast inventory guard:

```bash
npm run guard:example-coverage
```

Buildable examples should include `build.hxml`, `README.md`, and
`expected.stdout`. The runner compiles the example, runs the produced artifact
when applicable, and compares stdout so examples do not silently drift after
compiler changes. If an example needs checks beyond stdout, add `test.hxml` or
`test.sh`; the runner executes those example-specific checks after the stdout
diff.

Some examples are intentionally heavier and are **skipped** by `test:examples`.
Run those with:

```bash
npm run test:acceptance
```

## Included examples

- `hxhx-library-reflaxe-ocaml-plugin`: Stage3 plugin fixture (`--library`, macro hooks, classpath injection).
- `hxhx-js-todoapp`: lix-first JS todo app (`coconut.ui`, `tink_web`, `tink_sql` schema types) compiled via `hxhx --js <file>`.
- `hxhx-embedding-subprocess` (fixture): tiny success/failure modules used by `npm run hxhx:example:embedding-subprocess` to demonstrate embedding report + diagnostic capture.
