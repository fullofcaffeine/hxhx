# Terms You Must Know

Fast on-ramp glossary for beginners. Full glossary: `docs/00-project/GLOSSARY.md`.

1. **stage0**: upstream `haxe` binary used as oracle/bootstrap compiler.
2. **compat lane**: `--ocaml-eval` and `--compat --js <file>`; compatibility-first and may delegate to stage0.
3. **native lane**: `--ocaml` / `--js <file>`; linked Stage3 path.
4. **`--ocaml-eval`**: delegated OCaml lane (stage0 + reflaxe.ocaml injection).
5. **`--compat`**: pure upstream passthrough lane (stage0; no hxhx injection).
6. **`--ocaml`**: native linked OCaml backend path.
7. **`--js <file>`**: native linked JS backend path.
8. **linked-provider plugin**: manifest kind that names a Haxe provider type.
9. **ocaml-dynlink plugin**: native plugin artifact loaded at runtime (`.cmxs` / `.cma`).
10. **builtin backend**: backend linked into `hxhx` and shipped with the binary.
11. **portable profile**: default OCaml profile, compatibility-first semantics.
12. **metal profile**: strict native-leaning OCaml profile with verifier constraints.
13. **strict mode (`HXHX_FORBID_STAGE0=1`)**: fail if a path tries to delegate to stage0.
14. **replacement-ready**: gate bundle status proving scoped compatibility/readiness signals.
15. **Haxe-provider (legacy term)**: old wording; use `linked-provider` instead.
