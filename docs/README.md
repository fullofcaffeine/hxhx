# Documentation Map

Use this page as the docs index. If you are new, start with `docs/01-getting-started/START_HERE.md`.

## Beginner paths

- Compile Haxe code with `hxhx`: `docs/01-getting-started/START_HERE.md`
- Quickstart (compat/delegated lane): `docs/01-getting-started/QUICKSTART_COMPAT.md`
- Quickstart (native lane): `docs/01-getting-started/QUICKSTART_NATIVE.md`
- Beginner status snapshot: `docs/01-getting-started/WHAT_WORKS_TODAY.md`
- Use upstream `haxe` + `reflaxe.ocaml`: `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- Promote Reflaxe backends to native plugin artifacts: `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md`
- Validate native (non-delegating) `hxhx` lanes: `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
- Promote Reflaxe compilers/backends to native plugins: `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- Embed `hxhx` in another app (supported subprocess contract): `docs/02-user-guide/EMBEDDING.md`

## Terms and CI

- Glossary (plain language): `docs/00-project/GLOSSARY.md`
- CI workflows and gate meaning: `docs/00-project/CI_GATES.md`
- Delegated vs native execution modes: `docs/02-user-guide/concepts/execution_modes.md`
- Delegation truth table (what still routes to stage0): `docs/02-user-guide/concepts/what_delegates_today.md`

## Milestone labels (M13, M14, ...)

- `Mxx` labels are internal engineering milestone tags used by tests, docs, and beads.
- `M13`: OCaml tooling/output polish lanes (dune layout, `.mli`, source maps); see `test/M13MliIntegrationTest.hx`.
- `M14`: native backend/plugin/platform integration lanes; see `test/M14BackendRegistryIntegrationTest.hx`.
- Use these labels as contributor shorthand, not as beginner entrypoints.

## Architecture and policy

- Stage model and backend layering: `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
- Stage0 policy and strict mode behavior: `docs/00-project/STAGE0_POLICY.md`
- Dynamic/untyped boundary policy: `docs/00-project/DYNAMIC_UNTYPED_POLICY.md`
- Provenance and licensing policy: `docs/00-project/PROVENANCE_POLICY.md`
