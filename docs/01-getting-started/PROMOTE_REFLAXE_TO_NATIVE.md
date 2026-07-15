# Promote Reflaxe Backends to Native (Beginner Guide)

This guide explains two common goals from scratch:

1) compile Haxe code (including compiler-like code) to a native OCaml executable with upstream `haxe` + `reflaxe.ocaml`
2) promote a Reflaxe backend/provider to a native runtime-loaded plugin for `hxhx`

Use this page when you are new to the repo and need a clear “which path should I take?” answer.

Canonical promotion contract:

- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`

## Pick the right outcome

| Goal | Use this path | Result |
| --- | --- | --- |
| I want a native executable from Haxe sources | Upstream `haxe` + `reflaxe.ocaml` | Native OCaml executable (via dune) |
| I want `hxhx` to load a backend at runtime | `hxhx` native promotion lane | Native plugin artifact (`.cmxs` or `.cma`) + manifest |
| I want backend logic shipped inside `hxhx` binary | Builtin backend lane | No runtime plugin load; backend linked into dist build |

Important:

- A **plugin artifact** is not the same as a builtin backend.
- Plugin flow is best for iteration and external distribution.
- Builtin flow is best when you control `hxhx` distribution itself.

## Prerequisites

- Node.js + npm
- Haxe `4.3.7`
- OCaml + dune + ocaml-findlib

Quick setup in this repo:

```bash
npm install
npx lix download
npm run ci:guards
```

---

## Path A — Upstream `haxe` + `reflaxe.ocaml` native executable

This is the simplest path if you want native OCaml output without using `hxhx` plugin loading.

Inside this monorepo, `-lib reflaxe.ocaml` is already resolved by
`haxe_libraries/reflaxe.ocaml.hxml`. Outside this monorepo, prefer a released
or locally built package; use `haxelib dev` only when testing this unreleased
checkout from another project. Point at the repo root dev package so source
`_std` overrides are visible:

```bash
cd /path/to/my-haxe-app
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
```

Compile your Haxe project:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Compile and build native in one step:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

When this path is useful:

- you want upstream CLI behavior
- you need OCaml native build output
- you are not yet using `hxhx` native plugin loading

---

## Path B — `hxhx` native backend plugin promotion

This path creates a runtime-loadable plugin artifact for `hxhx` native backend selection.

### 1) Build `hxhx`

```bash
HXHX_BIN="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
echo "$HXHX_BIN"
```

### 2) Generate scaffold (optional but recommended)

```bash
bash scripts/hxhx/plugin-init.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --target-id js-native
```

### 3) Promote provider to native plugin artifact

```bash
bash scripts/hxhx/promote-backend-plugin.sh \
  --out-dir .tmp/promotion-demo \
  --plugin-id demo.native.plugin \
  --provider-type backend.js.JsBackend \
  --target-id js-native
```

Expected files:

- `.tmp/promotion-demo/backend-plugin.json`
- `.tmp/promotion-demo/plugins/demo_native_plugin.cmxs` (or `.cma` when using bytecode host)

### 4) Compile through native plugin selection

```bash
HXHX_FORBID_STAGE0=1 \
HXHX_TRACE_BACKEND_SELECTION=1 \
HXHX_TRACE_BACKEND_PROVIDERS=1 \
"$HXHX_BIN" \
  --js .tmp/promotion-demo/out/main.js \
  --hxhx-no-run \
  -cp src \
  -main Main \
  --hxhx-out .tmp/promotion-demo/out \
  -D hxhx_backend_provider=backend.js.JsBackend \
  -D hxhx_backend_plugin_manifest=.tmp/promotion-demo/backend-plugin.json
```

Expected marker in output:

- `backend_selected_impl=provider/js-native-wrapper`

---

## Path C — Builtin backend (no runtime plugin)

Builtin means the backend is linked into `hxhx` itself and selected without dynlink loading.

Use this when:

- you own the `hxhx` distribution build
- you want no runtime plugin artifact management

For architecture and layering:

- `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
- `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md`

---

## Planned M22 — one target core with optional `hxhx` services

M22 plans the next product step, but none of the commands in this section exist
yet. Keep using Paths A, B, and C above as current truth.

The future “two-in-one” target keeps one host-neutral core and chooses only its
adapter at the composition root:

- evaluated host-neutral development through upstream Haxe/Reflaxe;
- native host-neutral execution after compiling the same core through
  `reflaxe.ocaml`;
- `hxhx`-integrated native plugin execution with negotiated services;
- `hxhx`-integrated builtin execution with the same target-core factory.

Native execution does not imply privileged compiler access. Integrated forms
must request typed/versioned facts or actions, and missing correctness-critical
facts fail before emission. Host conditionals and native externs stay in
adapter/transport modules rather than semantic lowering and printers.

The existing `ocaml_profile=portable|metal` switch is a separate output policy,
not an M22 service-access preset. See
`docs/00-project/REFLAXE_NATIVE_COMPILER_SDK_M22_PLAN.md` for the planning-only
contract.

---

## Recommended validation commands

Backend plugin promotion smoke:

```bash
npm run test:hxhx:promotion-backend-smoke
```

Plugin runtime loading smoke:

```bash
npm run test:hxhx:native-plugin-runtime-smoke
```

Reflaxe.elixir external pilot (external fetched workflow):

```bash
npm run test:hxhx:reflaxe-elixir-todo-pilot
```

---

## Troubleshooting

- `native plugin artifact not found`
  - check `backend.entry` path in manifest is relative to manifest location and points to existing `.cmxs`/`.cma`.
- `backend provider class not found`
  - verify `--provider-type` is a valid compiled Haxe type path.
- dynlink load failures
  - check host/toolchain compatibility (`ocamlopt`, `dune`, runtime libs) and artifact extension (`.cmxs` for native host, `.cma` for bytecode host).
- stage0 usage unexpectedly appears
  - run with `HXHX_FORBID_STAGE0=1` to force fail-fast on accidental delegation.

## Related docs

- `docs/01-getting-started/START_HERE.md`
- `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`
