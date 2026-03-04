# Start Here

This page is the fastest way to pick the right workflow.

First stop (beginner shortcuts):

- Lane chooser: `docs/01-getting-started/CHOOSE_YOUR_LANE.md`
- Mini glossary (~15 terms): `docs/01-getting-started/TERMS_YOU_MUST_KNOW.md`

If you see unfamiliar terms, check `docs/00-project/GLOSSARY.md`.
For a full docs map, see `docs/README.md`.

Canonical definitions for all paths:

- Beginner truth table (lanes + profiles + gates): `docs/02-user-guide/concepts/execution_modes.md`
- Delegation truth table (exact lane commands): `docs/02-user-guide/concepts/what_delegates_today.md`
- Gate/workflow meanings: `docs/00-project/CI_GATES.md`
- Beginner status snapshot: `docs/01-getting-started/WHAT_WORKS_TODAY.md`
- Dedicated lane chooser page: `docs/01-getting-started/CHOOSE_YOUR_LANE.md`

## CLI Cutover Rules (Beginner)

- Use direct lane flags: `--ocaml`, `--ocaml-eval`, `--compat`, and canonical `--js <file>`.
- `--target` was removed on purpose (hard cutover, no compatibility shim).
- `--target-id` is still valid, but only in plugin scaffold/build scripts (for example `plugin-init.sh`).
- Performance tip for heavy bootstrap/source runs: if `which haxe` points to a Lix shim (`.../lix/bin/haxeshim.js`), prefer a native binary explicitly, for example:
  - `HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --fast`

## Choose your path

### 1) I want to compile Haxe code right now

Use `hxhx` first.

```bash
npm install
npx lix download
bash scripts/hxhx/build-hxhx.sh
```

Then run `hxhx` with your preferred target.

Start here next:
- `README.md`
- `docs/01-getting-started/QUICKSTART_COMPAT.md`
- `docs/01-getting-started/QUICKSTART_NATIVE.md`
- `docs/01-getting-started/TESTING.md`
- `docs/02-user-guide/concepts/execution_modes.md`

### 2) I want mainstream `haxe` + `reflaxe.ocaml`

Use this when you want upstream CLI behavior and OCaml output from `reflaxe.ocaml`.

```bash
haxelib dev reflaxe.ocaml /path/to/hxhx
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

Read:
- `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- `packages/reflaxe.ocaml/README.md`
- `docs/02-user-guide/concepts/execution_modes.md`

### 3) I want the `hxhx` native lane

Use this when you are validating non-delegating compiler paths.

```bash
npm run ci:guards
npm run test:hxhx-targets
npm run test:upstream:replacement-ready:strict
```

Read:
- `docs/00-project/STAGE0_POLICY.md`
- `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/00-project/CI_GATES.md`

### 4) I want to promote a Reflaxe compiler/target to native plugin artifacts

Use this when you want a runtime-loaded backend plugin instead of only linked-provider (Haxe type) plugin mode.
For `reflaxe.elixir`, use the external fetched pilot workflow (no vendoring in this repo).

```bash
bash scripts/hxhx/plugin-init.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --target-id js-native

bash scripts/hxhx/promote-backend-plugin.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --provider-type backend.js.JsBackend \
  --target-id js-native
```

Read:
- `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md`
- `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
- `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md`
- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/00-project/CI_GATES.md`

### 5) I want to embed `hxhx` into another application

Use this when your host app should spawn `hxhx` as a subprocess and collect machine-readable reports/diagnostics.

```bash
npm run hxhx:example:embedding-subprocess
```

Read:
- `docs/02-user-guide/EMBEDDING.md`
- `docs/02-user-guide/HXHX_DISTRIBUTION.md`
- `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`

## Plugin vs builtin backend (quick)

| Mode | What it is | Best for | Tradeoff |
| --- | --- | --- | --- |
| Plugin (OCaml dynlink artifact: `.cmxs` / `.cma`) | Native artifact loaded at runtime via manifest | Fast iteration and external backends | ABI/toolchain coupling |
| Builtin | Backend shipped inside `hxhx` binary | Stable default distribution path | Requires repo/release integration |

## Notes for contributors

- User-facing language in this repo should prefer **delegated** vs **native**.
- Stage labels (`stage0`…`stage4`) are architecture terms and mainly belong in contributor/architecture docs.

## Additional references

- `docs/README.md`
- `docs/00-project/GLOSSARY.md`
- `docs/01-getting-started/TESTING.md`
- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/native_mode_pipeline.md`
- `docs/02-user-guide/concepts/targets_backends_plugins.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
- `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md`

## What are `M13` / `M14` labels?

- `Mxx` labels are contributor milestone tags used in test file names and beads.
- `M13` mainly covers OCaml tooling/output polish checks (for example, `test/M13MliIntegrationTest.hx`).
- `M14` mainly covers native backend/plugin/platform integration checks (for example, `test/M14BackendRegistryIntegrationTest.hx`).
- They are useful for contributors, but not required to follow beginner workflows.
