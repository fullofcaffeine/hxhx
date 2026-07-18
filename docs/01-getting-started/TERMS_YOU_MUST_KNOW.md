# Terms You Must Know

Fast on-ramp glossary for beginners. Full glossary: `docs/00-project/GLOSSARY.md`.

1. **stage0**: the already-installed upstream `haxe` binary used to build the
   first `hxhx` or to compare behavior. It is a starter/oracle tool, not proof
   that `hxhx` itself handled a workload.
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
13. **strict mode (`HXHX_FORBID_STAGE0=1`)**: after the `hxhx` binary exists,
    fail if that compiler invocation tries to delegate the user workload to
    stage0. This makes the result evidence about native `hxhx`. It does not ban
    using stage0 earlier for bootstrap, using upstream source as a separate
    behavior oracle, or invoking downstream tools such as clang.
14. **replacement-ready**: gate bundle status proving scoped compatibility/readiness signals.
15. **Haxe-provider (legacy term)**: old wording; use `linked-provider` instead.
16. **shared native Reflaxe plugin (planned)**: one versioned ABI and promoted
    payload intended to load in both stock Haxe and `hxhx`. Prefer one identical
    binary; if proven OCaml host constraints require it, only the thin loader
    shell may differ.
17. **loader shell**: host-specific loading/ABI glue around the shared payload.
    It must not contain target semantics, so different shells do not become two
    compiler implementations.
