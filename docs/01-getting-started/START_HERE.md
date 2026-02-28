# Start Here

This page is the fastest way to pick the right workflow.

If you see unfamiliar terms, check `docs/00-project/GLOSSARY.md`.

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
- `docs/01-getting-started/TESTING.md`

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

### 4) I want to promote a Reflaxe compiler/target to native plugin artifacts

Use this when you want a runtime-loaded backend plugin instead of only Haxe-provider mode.

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
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
- `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md`

## Plugin vs builtin backend (quick)

| Mode | What it is | Best for | Tradeoff |
| --- | --- | --- | --- |
| Plugin (OCaml dynlink artifact: `.cmxs` / `.cma`) | Native artifact loaded at runtime via manifest | Fast iteration and external backends | ABI/toolchain coupling |
| Builtin | Backend shipped inside `hxhx` binary | Stable default distribution path | Requires repo/release integration |

## Notes for contributors

- User-facing language in this repo should prefer **delegated** vs **native**.
- Stage labels (`stage0`…`stage4`) are architecture terms and mainly belong in contributor/architecture docs.

## Additional references

- `docs/00-project/GLOSSARY.md`
- `docs/01-getting-started/TESTING.md`
- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/native_mode_pipeline.md`
- `docs/02-user-guide/concepts/targets_backends_plugins.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
- `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md`
