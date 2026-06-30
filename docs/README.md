# Documentation Map

Use this page as the docs index. If you are new, start with `docs/01-getting-started/START_HERE.md`.

## Beginner paths

- Compile Haxe code with `hxhx`: `docs/01-getting-started/START_HERE.md`
- Choose the right lane quickly: `docs/01-getting-started/CHOOSE_YOUR_LANE.md`
- Beginner mini glossary (~15 terms): `docs/01-getting-started/TERMS_YOU_MUST_KNOW.md`
- Quickstart (compat/delegated lane): `docs/01-getting-started/QUICKSTART_COMPAT.md`
- Quickstart (native lane): `docs/01-getting-started/QUICKSTART_NATIVE.md`
- Beginner status snapshot: `docs/01-getting-started/WHAT_WORKS_TODAY.md`
- Use upstream `haxe` + `reflaxe.ocaml`: `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- Use `reflaxe.ocaml` through `hxhx`: `docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md`
- `reflaxe.ocaml` production install/use/troubleshooting: `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`
- Choose a Reflaxe promotion path: `docs/01-getting-started/CHOOSE_A_REFLAXE_PROMOTION_PATH.md`
- Promote Reflaxe backends to native plugin artifacts: `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md`
- Validate native (non-delegating) `hxhx` lanes: `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
- Promote Reflaxe compilers/backends to native plugins: `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- Embed `hxhx` in another app (supported subprocess contract): `docs/02-user-guide/EMBEDDING.md`

## Terms and CI

- Glossary (plain language): `docs/00-project/GLOSSARY.md`
- CI workflows and gate meaning: `docs/00-project/CI_GATES.md`
- `reflaxe.ocaml` product contract: `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`
- `reflaxe.ocaml` upstream-Haxe validation matrix: `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.md`
- `reflaxe.ocaml` runtime/stdlib closure audit: `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.md`
- `reflaxe.ocaml` performance credibility baseline: `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`
- Reflaxe promotion matrix contract: `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
- Reflaxe promotion matrix tradeoffs: `docs/00-project/REFLAXE_PROMOTION_MATRIX_TRADEOFFS.md`
- Public `Scoped 1.0` / `Full 1.0` claim checklist: `docs/00-project/PUBLIC_1_0_CHECKLIST.md`
- North-star product goals and planning owners: `docs/00-project/NORTH_STAR_GOALS.md`
- Weekly scheduled-gate audit runbook: `docs/00-project/WEEKLY_CI_EVIDENCE.md`
- Delegated vs native execution modes: `docs/02-user-guide/concepts/execution_modes.md`
- Delegation truth table (what still routes to stage0): `docs/02-user-guide/concepts/what_delegates_today.md`

## Milestone labels (M13, M14, ...)

- `Mxx` labels are internal engineering milestone tags used by tests, docs, and beads.
- `M13`: OCaml tooling/output polish lanes (dune layout, `.mli`, source maps); see `test/M13MliIntegrationTest.hx`.
- `M14`: native backend/plugin/platform integration lanes; see `test/M14BackendRegistryIntegrationTest.hx`.
- Use these labels as contributor shorthand, not as beginner entrypoints.

## Architecture and policy

- Stage model and backend layering: `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
- C++ native target boundary: `docs/02-user-guide/HXHX_CPP_NATIVE_TARGET_BOUNDARY.md`
- C++ helper rendering policy: `docs/00-project/CPP_HELPER_RENDERING_POLICY.md`
- C++ target runtime/helper policy: `docs/00-project/CPP_TARGET_RUNTIME_POLICY.md`
- C++ Reflect/Dynamic support audit:
  `docs/00-project/CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`
- Serializer/Unserializer behavior matrix:
  `docs/00-project/SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`
- Float/NaN/Infinity numeric review gate:
  `docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md`
- Source-native runtime packaging strategy: `docs/02-user-guide/SOURCE_NATIVE_RUNTIME_PACKAGING_STRATEGY.md`
- `.cross.hx` vs `_std` beginner guide: `docs/02-user-guide/CROSS_AND_STAGED_STDLIB_GUIDE.md`
- Reflaxe family cross-override audit: `docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_AUDIT.md`
- Reflaxe family cross-override matrix: `docs/00-project/REFLAXE_FAMILY_CROSS_OVERRIDE_MATRIX.md`
- Stage0 policy and strict mode behavior: `docs/00-project/STAGE0_POLICY.md`
- Dynamic/untyped boundary policy: `docs/00-project/DYNAMIC_UNTYPED_POLICY.md`
- OCaml scoped raw-injection authority policy: `docs/00-project/OCAML_SCOPED_RAW_INJECTION_AUTHORITY.md`
- Provenance and licensing policy: `docs/00-project/PROVENANCE_POLICY.md`
