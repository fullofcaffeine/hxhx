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

Native frontend hook:

- This example enables `-D hih_native_parser` by default (see `build.hxml`).
- In that mode, parsing is performed by stub OCaml modules copied from:
  - `std/runtime/HxHxNativeLexer.ml`
  - `std/runtime/HxHxNativeParser.ml`
- This matches the upstream bootstrap strategy (#6843): keep lexer/parser native
  while reimplementing the rest of the compiler pipeline in Haxe.
- Wire format: `docs/02-user-guide/HXHX_NATIVE_FRONTEND_PROTOCOL.md`
- Upstream alignment: `CompilerDriver` embeds a tiny subset of fixtures shaped
  after upstream `tests/misc` module-resolution files (and asserts native vs
  pure-Haxe parser agreement for this subset).

Related docs:

- `docs/02-user-guide/ML2HX_SUBSET_CONTRACT.md`
- `docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md`
