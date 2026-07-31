# hih-compiler (Haxe-in-Haxe compiler, Stage 2 skeleton)

This example is the **seed project** for a production-grade Haxe-in-Haxe compiler that we will grow over time.

Target goals:

- Haxe **4.3.7** compatibility
- Eventually supports **macros**

Reference implementation (OCaml Haxe compiler source):

- `vendor/haxe` (or your local upstream Haxe checkout path)

This is intentionally kept as an **acceptance-only** example (it’s allowed to be heavier and more compiler-shaped).
Run it via:

```bash
npm run test:acceptance
```

Frontend ownership:

- This workload uses the same Haxe-authored `HxParser` as product and bootstrap
  compiler builds.
- Earlier versions selected a handwritten OCaml parser with a build define.
  That duplicate semantic path was retired after it interpreted valid source
  differently from `HxParser`.
- Upstream alignment: `CompilerDriver` embeds a tiny subset of fixtures shaped
  after upstream `tests/misc` module-resolution files and checks the normal
  `ParserStage` result against direct `HxParser` output.

Related docs:

- `docs/02-user-guide/ML2HX_SUBSET_CONTRACT.md`
- `docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md`
